#' Unified LLM Classifier
#'
#' @description
#' Create a backend-agnostic classifier with two confidence scoring methods:
#'
#' - `generate()`: Adaptive constrained generation with divergence-aware
#'   confidence. Budget-controlled via `max_calls`. Makes 1 to `max_calls`
#'   constrained API calls.
#' - `classify()`: Multi-call completion scoring with geometric-mean
#'   normalization. Always exact. Makes N calls for N labels.
#'
#' @param backend A backend object created by [ollama_backend()],
#'   [vllm_backend()], [sglang_backend()], or [llamacpp_backend()].
#'
#' @return A classifier object (list of closures) usable with the S3 generics
#'   [generate()], [classify()], [batch_generate()], [batch_classify()].
#'
#' @export
#' @examples
#' \dontrun{
#' backend <- ollama_backend("llama3.2")
#' classifier <- llm_classifier(backend)
#'
#' result <- classify(
#'   classifier,
#'   text = "I love this product!",
#'   choices = c("positive", "negative", "neutral")
#' )
#' print(result$prediction)
#' print(result$confidence)
#' }
llm_classifier <- function(backend) {
  labels_fn <- get_choice_labels
  build_prompt <- build_classification_prompt

  # --- Helper: get token context for this backend ---
  get_token_context <- function() {
    if (isTRUE(backend$supports_bare_label_constraint)) NULL
    else OLLAMA_JSON_LABEL_CONTEXT
  }

  # --- Helper: tokenize all labels ---
  tokenize_labels <- function(labels, token_context) {
    purrr::map(labels, ~ {
      tokens <- backend$tokenize(.x, context = token_context)
      # If tokens are numeric IDs (as strings), create placeholder names
      if (length(tokens) == 0) {
        tokens <- .x
      }
      tokens
    }) |> purrr::set_names(labels)
  }

  # --- Helper: extract step logprobs (filter structural tokens) ---
  extract_step_logprobs <- function(response, token_sequences, cluster_labels) {
    if (is.null(response$logprobs) || length(response$logprobs) == 0) {
      return(list())
    }

    valid_tokens <- unique(unlist(
      token_sequences[cluster_labels], use.names = FALSE
    ))

    purrr::map(response$logprobs, function(tlp) {
      top <- tlp$top_logprobs
      if (is.null(top) || length(top) == 0) return(NULL)
      filtered <- top[names(top) %in% valid_tokens]
      if (length(filtered) > 0) filtered else NULL
    }) |> purrr::compact()
  }

  # ==================================================================
  # generate() — Adaptive trie-masked generation
  # ==================================================================

  generate_fn <- function(text, choices, system_prompt = NULL, max_calls = 1L) {
    labels <- labels_fn(choices)
    prompt <- build_prompt(text, choices, system_prompt)
    messages <- list(
      list(role = "system", content = prompt$system),
      list(role = "user", content = prompt$user)
    )

    # 1. Tokenize labels
    token_context <- get_token_context()
    token_sequences <- tokenize_labels(labels, token_context)

    # 2. Build trie and determine top_logprobs K
    trie <- label_trie()
    for (label in labels) {
      trie <- trie_insert(trie, label, token_sequences[[label]])
    }
    k <- max(trie_max_branching(trie), 5L)

    # 3. Adaptive resolution loop
    all_step_logprobs <- purrr::map(labels, ~ numeric(0)) |>
      purrr::set_names(labels)
    all_scored_lengths <- purrr::map_int(labels, ~ 0L) |>
      purrr::set_names(labels)
    calls_made <- 0L

    frontier <- list(list(labels = labels, resolved_length = 0L))

    while (length(frontier) > 0 && (is.null(max_calls) || calls_made < max_calls)) {
      cluster <- frontier[[1]]
      frontier <- frontier[-1]

      cluster_labels <- cluster$labels
      resolved_len <- cluster$resolved_length

      # Constrained call
      response <- backend$chat(
        messages = messages,
        temperature = 0,
        constrain_labels = cluster_labels,
        logprobs = TRUE,
        top_logprobs = k
      )
      calls_made <- calls_made + 1L

      # Extract step logprobs
      step_lps <- extract_step_logprobs(response, token_sequences, cluster_labels)

      # Score labels
      winning_label <- response$label
      cluster_token_seqs <- token_sequences[cluster_labels]

      cluster_scores <- score_labels_from_winning_path(
        cluster_token_seqs, winning_label, step_lps
      )
      cluster_lengths <- get_scored_lengths(cluster_token_seqs, winning_label)

      # Accumulate newly scored logprobs
      for (label in cluster_labels) {
        new_len <- cluster_lengths[[label]]
        if (new_len > resolved_len) {
          new_lps <- numeric(0)
          for (i in seq(resolved_len + 1L, new_len)) {
            token <- token_sequences[[label]][i]
            if (i <= length(step_lps) && token %in% names(step_lps[[i]])) {
              new_lps <- c(new_lps, step_lps[[i]][[token]])
            } else {
              new_lps <- c(new_lps, -Inf)
            }
          }
          all_step_logprobs[[label]] <- c(all_step_logprobs[[label]], new_lps)
          all_scored_lengths[[label]] <- new_len
        }
      }

      # Identify sub-clusters
      sub_clusters <- identify_unresolved_clusters(
        cluster_token_seqs, cluster_lengths
      )
      frontier <- c(frontier, sub_clusters)
    }

    # 4. Compute final scores
    raw_scores <- purrr::map_dbl(labels, ~ {
      lps <- all_step_logprobs[[.x]]
      if (length(lps) > 0) geometric_mean_logprob(lps) else -Inf
    }) |> purrr::set_names(labels)

    coverage <- purrr::map_dbl(labels, ~ {
      lps <- all_step_logprobs[[.x]]
      total <- length(token_sequences[[.x]])
      if (total > 0) length(lps) / total else 1
    }) |> purrr::set_names(labels)

    probs <- stable_softmax(raw_scores)
    prediction <- names(probs)[which.max(probs)]
    is_approximate <- any(coverage < 1.0)

    classification_result(
      prediction = prediction,
      confidence = unname(probs[prediction]),
      probabilities = probs,
      method = "adaptive_generate",
      approximate = is_approximate,
      coverage = coverage,
      n_calls = calls_made,
      raw_response = list(
        logprobs = raw_scores,
        token_sequences = token_sequences
      )
    )
  }

  # ==================================================================
  # classify() — Multi-call completion scoring
  # ==================================================================

  classify_fn <- function(text, choices, system_prompt = NULL) {
    labels <- labels_fn(choices)
    prompt <- build_prompt(text, choices, system_prompt)
    messages <- list(
      list(role = "system", content = prompt$system),
      list(role = "user", content = prompt$user)
    )

    raw_scores <- purrr::map_dbl(labels, ~ {
      scoring <- backend$score(messages, .x)
      token_lps <- purrr::map_dbl(scoring$logprobs, "logprob", .default = 0)
      if (length(token_lps) > 0) geometric_mean_logprob(token_lps)
      else -Inf
    }) |> purrr::set_names(labels)

    probs <- stable_softmax(raw_scores)
    prediction <- names(probs)[which.max(probs)]

    classification_result(
      prediction = prediction,
      confidence = unname(probs[prediction]),
      probabilities = probs,
      method = "multi_call",
      approximate = FALSE,
      n_calls = length(labels),
      raw_response = list(logprobs = raw_scores)
    )
  }

  # ==================================================================
  # Batch variants
  # ==================================================================

  batch_generate_fn <- function(texts, choices, system_prompt = NULL,
                                 max_calls = 1L) {
    purrr::map(texts, ~ generate_fn(.x, choices, system_prompt, max_calls))
  }

  batch_classify_fn <- function(texts, choices, system_prompt = NULL) {
    purrr::map(texts, ~ classify_fn(.x, choices, system_prompt))
  }

  structure(
    list(
      generate = generate_fn,
      classify = classify_fn,
      batch_generate = batch_generate_fn,
      batch_classify = batch_classify_fn
    ),
    class = "llm_classifier"
  )
}


# =========================================================================
# S3 method dispatch
# =========================================================================

#' @export
generate.llm_classifier <- function(classifier, text, choices,
                                     system_prompt = NULL, ..., max_calls = 1L) {
  classifier$generate(text, choices, system_prompt, max_calls)
}

#' @export
classify.llm_classifier <- function(classifier, text, choices,
                                     system_prompt = NULL, ...) {
  classifier$classify(text, choices, system_prompt)
}

#' @export
batch_generate.llm_classifier <- function(classifier, texts, choices,
                                            system_prompt = NULL, ...,
                                            max_calls = 1L) {
  classifier$batch_generate(texts, choices, system_prompt, max_calls)
}

#' @export
batch_classify.llm_classifier <- function(classifier, texts, choices,
                                            system_prompt = NULL, ...) {
  classifier$batch_classify(texts, choices, system_prompt)
}
