#' LLM Classifier (Backend-Agnostic)
#'
#' @description
#' Create a classifier that works with any inference backend. Accepts a
#' backend created by [vllm_backend()], [sglang_backend()], or
#' [llamacpp_backend()]. The public API mirrors [ollama_classifier()] so that
#' switching engines requires changing only the constructor.
#'
#' @param backend A backend object created by one of the backend constructors
#'   (e.g., [vllm_backend()]).
#'
#' @return A classifier environment (list-like object) with the same methods
#'   as [ollama_classifier()].
#'
#' @export
#' @examples
#' \dontrun{
#' backend <- vllm_backend("meta-llama/Llama-3.2-3B-Instruct")
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
  labels <- get_choice_labels
  build_prompt <- build_classification_prompt
  schema <- build_json_schema
  forced <- build_forced_schema
  extract_lp <- extract_logprob_sum
  softmax_fn <- stable_softmax

  # --- Generate ---
  generate_fn <- function(text, choices, system_prompt = NULL) {
    lbl <- labels(choices)
    prompt <- build_prompt(text, choices, system_prompt)
    s <- schema(lbl)

    resp <- backend$chat(
      messages = list(
        list(role = "system", content = prompt$system),
        list(role = "user", content = prompt$user)
      ),
      temperature = 0,
      guided_json = s
    )

    parsed <- jsonlite::fromJSON(resp$content, simplifyVector = FALSE)
    parsed$label %||% ""
  }

  # --- Score ---
  get_logprob <- function(system, user, choice) {
    s <- forced(choice)
    resp <- backend$chat(
      messages = list(
        list(role = "system", content = system),
        list(role = "user", content = user)
      ),
      temperature = 0,
      guided_json = s,
      logprobs = TRUE
    )
    extract_lp(resp)
  }

  score_fn <- function(text, choices, system_prompt = NULL) {
    lbl <- labels(choices)
    prompt <- build_prompt(text, choices, system_prompt)

    logprobs <- purrr::map_dbl(lbl, ~ get_logprob(prompt$system, prompt$user, .x))
    names(logprobs) <- lbl

    probs <- softmax_fn(logprobs)
    prediction <- names(probs)[which.max(probs)]

    classification_result(
      prediction = prediction,
      confidence = probs[prediction],
      probabilities = probs,
      raw_response = list(logprobs = logprobs)
    )
  }

  # --- Classify ---
  classify_fn <- function(text, choices, system_prompt = NULL) {
    score_fn(text, choices, system_prompt)
  }

  # --- Batch ---
  batch_generate_fn <- function(texts, choices, system_prompt = NULL) {
    purrr::map_chr(texts, ~ generate_fn(.x, choices, system_prompt))
  }

  batch_score_fn <- function(texts, choices, system_prompt = NULL) {
    purrr::map(texts, ~ score_fn(.x, choices, system_prompt))
  }

  batch_classify_fn <- function(texts, choices, system_prompt = NULL) {
    purrr::map(texts, ~ classify_fn(.x, choices, system_prompt))
  }

  structure(
    list(
      generate = generate_fn,
      score = score_fn,
      classify = classify_fn,
      batch_generate = batch_generate_fn,
      batch_score = batch_score_fn,
      batch_classify = batch_classify_fn
    ),
    class = "llm_classifier"
  )
}

#' @export
generate.llm_classifier <- function(classifier, text, choices,
                                     system_prompt = NULL, ...) {
  classifier$generate(text, choices, system_prompt)
}

#' @export
score.llm_classifier <- function(classifier, text, choices,
                                  system_prompt = NULL, ...) {
  classifier$score(text, choices, system_prompt)
}

#' @export
classify.llm_classifier <- function(classifier, text, choices,
                                     system_prompt = NULL, ...) {
  classifier$classify(text, choices, system_prompt)
}

#' @export
batch_generate.llm_classifier <- function(classifier, texts, choices,
                                            system_prompt = NULL, ...) {
  classifier$batch_generate(texts, choices, system_prompt)
}

#' @export
batch_score.llm_classifier <- function(classifier, texts, choices,
                                         system_prompt = NULL, ...) {
  classifier$batch_score(texts, choices, system_prompt)
}

#' @export
batch_classify.llm_classifier <- function(classifier, texts, choices,
                                            system_prompt = NULL, ...) {
  classifier$batch_classify(texts, choices, system_prompt)
}
