#' Unified LLM Classifier
#'
#' @description
#' Create a backend-agnostic classifier with two confidence scoring methods:
#'
#' - `generate()`: Hierarchical constrained generation. A single constrained
#'   call produces a probability distribution over all labels using
#'   divergence-aware logprobs from the winning path. When `max_calls > 1`,
#'   supplementary calls resolve clusters of labels that share a token prefix
#'   but diverge from the winner — but only to **reproportion** probability
#'   mass *within* each cluster, never changing between-group totals. This
#'   guarantees accuracy never degrades as the call budget grows.
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
  # generate() — Hierarchical constrained generation
  # ==================================================================

  generate_fn <- function(text, choices, system_prompt = NULL, max_calls = 1L) {
    labels <- labels_fn(choices)
    prompt <- build_prompt(text, choices, system_prompt)
    messages <- list(
      list(role = "system", content = prompt$system),
      list(role = "user", content = prompt$user)
    )

    # 1. Tokenize labels in the backend's constraint context
    token_context <- get_token_context()
    token_sequences <- tokenize_labels(labels, token_context)

    # 2. Build trie and determine required top_logprobs K
    trie <- label_trie()
    for (label in labels) {
      trie <- trie_insert(trie, label, token_sequences[[label]])
    }
    k <- max(trie_max_branching(trie), 5L)

    # 3. First constrained call over ALL labels
    response <- backend$chat(
      messages = messages,
      temperature = 0,
      constrain_labels = labels,
      logprobs = TRUE,
      top_logprobs = k
    )
    calls_made <- 1L

    step_lps <- extract_step_logprobs(response, token_sequences, labels)

    winning_label <- response$label
    cluster_lengths <- get_scored_lengths(token_sequences, winning_label)

    # Accumulate per-label logprobs and coverage for the initial call.
    # All logprobs come from the same constraint context (all labels), so
    # the distribution produced below is internally consistent.
    all_step_logprobs <- purrr::map(labels, ~ numeric(0)) |>
      purrr::set_names(labels)
    all_scored_lengths <- purrr::map_int(labels, ~ 0L) |>
      purrr::set_names(labels)

    for (label in labels) {
      scored_len <- cluster_lengths[[label]]
      lps <- numeric(0)
      if (scored_len > 0L) {
        for (i in seq_len(scored_len)) {
          token <- token_sequences[[label]][i]
          if (i <= length(step_lps) && token %in% names(step_lps[[i]])) {
            lps <- c(lps, step_lps[[i]][[token]])
          } else {
            lps <- c(lps, -Inf)
          }
        }
      }
      all_step_logprobs[[label]] <- lps
      all_scored_lengths[[label]] <- scored_len
    }

    # 4. Initial probability distribution (single constraint context)
    raw_scores <- purrr::map_dbl(labels, ~ {
      lps <- all_step_logprobs[[.x]]
      if (length(lps) > 0) geometric_mean_logprob(lps) else -Inf
    }) |> purrr::set_names(labels)

    probabilities <- stable_softmax(raw_scores)

    # 5. Recursive cluster resolution via reproportioning.
    #
    # Identify clusters of >=2 labels that share a scored prefix but diverge
    # from the winner. For each cluster, make a constrained call over only
    # the cluster's labels, compute divergence-based relative weights (softmax
    # of geometric-mean scores), and redistribute the cluster's total
    # probability mass accordingly. Between-group probabilities are locked, so
    # accuracy can only improve or stay the same, never degrade.
    frontier <- identify_unresolved_clusters(token_sequences, all_scored_lengths)

    while (length(frontier) > 0 && (is.null(max_calls) || calls_made < max_calls)) {
      cluster <- frontier[[1]]
      frontier <- frontier[-1]

      cluster_labels <- cluster$labels

      # Only resolve clusters with >=2 labels. Singletons are already fixed:
      # their probability is set by the between-group distribution and no
      # reproportioning call would change it.
      if (length(cluster_labels) < 2L) next

      # Constrained call over only this cluster's labels
      cluster_response <- backend$chat(
        messages = messages,
        temperature = 0,
        constrain_labels = cluster_labels,
        logprobs = TRUE,
        top_logprobs = k
      )
      calls_made <- calls_made + 1L

      cluster_step_lps <- extract_step_logprobs(
        cluster_response, token_sequences, cluster_labels
      )

      # Score cluster labels from the subset call
      cluster_winner <- cluster_response$label
      cluster_token_seqs <- token_sequences[cluster_labels]

      sub_lengths <- get_scored_lengths(cluster_token_seqs, cluster_winner)

      # Replace per-label logprobs for cluster members (NOT append — mixing
      # logprobs from different constraint contexts corrupts the geometric
      # mean). The replacement is only used to compute relative weights below.
      for (label in cluster_labels) {
        new_len <- sub_lengths[[label]]
        if (new_len > all_scored_lengths[[label]]) {
          new_lps <- numeric(0)
          for (i in seq_len(new_len)) {
            token <- token_sequences[[label]][i]
            if (i <= length(cluster_step_lps) &&
                token %in% names(cluster_step_lps[[i]])) {
              new_lps <- c(new_lps, cluster_step_lps[[i]][[token]])
            } else {
              new_lps <- c(new_lps, -Inf)
            }
          }
          all_step_logprobs[[label]] <- new_lps
          all_scored_lengths[[label]] <- new_len
        }
      }

      # Reproportion: redistribute the cluster's total probability mass
      # among its members using softmax of geometric-mean scores. The sum
      # of cluster probabilities is invariant; only within-cluster shares
      # change.
      cluster_total <- sum(unname(probabilities[cluster_labels]))

      cluster_raw <- purrr::map_dbl(cluster_labels, ~ {
        lps <- all_step_logprobs[[.x]]
        if (length(lps) > 0) geometric_mean_logprob(lps) else -Inf
      }) |> purrr::set_names(cluster_labels)

      cluster_weights <- stable_softmax(cluster_raw)

      for (label in cluster_labels) {
        probabilities[[label]] <- cluster_total * cluster_weights[[label]]
      }

      # Identify sub-clusters within this cluster for further resolution
      sub_clusters <- identify_unresolved_clusters(
        cluster_token_seqs, sub_lengths
      )
      frontier <- c(frontier, sub_clusters)
    }

    # 6. Compute coverage and final values
    coverage <- purrr::map_dbl(labels, ~ {
      total <- length(token_sequences[[.x]])
      scored <- all_scored_lengths[[.x]]
      if (total > 0) scored / total else 1
    }) |> purrr::set_names(labels)

    is_approximate <- any(coverage < 1.0)
    prediction <- names(probabilities)[which.max(probabilities)]

    classification_result(
      prediction = prediction,
      confidence = unname(probabilities[prediction]),
      probabilities = probabilities,
      method = "adaptive_generate",
      approximate = is_approximate,
      coverage = coverage,
      n_calls = calls_made,
      raw_response = list(
        logprobs = raw_scores,
        token_sequences = token_sequences,
        step_logprobs = all_step_logprobs,
        scored_lengths = all_scored_lengths
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

    # Score each label as a completion of the prompt. Accumulate both the
    # geometric-mean score and the per-token logprob list in a single pass
    # (one API call per label — matches Python v0.6.0).
    per_label <- purrr::map(labels, ~ {
      scoring <- backend$score(messages, .x)
      token_lps <- purrr::map_dbl(scoring$logprobs, "logprob", .default = 0)
      list(
        score = if (length(token_lps) > 0) geometric_mean_logprob(token_lps) else -Inf,
        token_logprobs = token_lps
      )
    }) |> purrr::set_names(labels)

    raw_scores <- purrr::map_dbl(per_label, "score") |> purrr::set_names(labels)
    logprob_details <- purrr::map(per_label, "token_logprobs")

    probs <- stable_softmax(raw_scores)
    prediction <- names(probs)[which.max(probs)]

    classification_result(
      prediction = prediction,
      confidence = unname(probs[prediction]),
      probabilities = probs,
      method = "multi_call",
      approximate = FALSE,
      n_calls = length(labels),
      raw_response = list(
        logprobs = raw_scores,
        token_logprobs = logprob_details
      )
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
