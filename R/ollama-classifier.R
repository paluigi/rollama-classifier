#' Ollama Classifier
#'
#' @description
#' Create a classifier that uses the Ollama REST API for text classification.
#' Provides constrained output generation via JSON schema and multi-call
#' evaluation with softmax for calibrated probability scores.
#'
#' @param model Character. Model name to use (e.g., `\"llama3.2\"`).
#' @param base_url Character. Base URL of the Ollama server.
#'   Defaults to `\"http://localhost:11434\"`.
#'
#' @return A classifier environment (list-like object) with methods:
#' \describe{
#'   \item{generate(text, choices, system_prompt)}{Constrained output only (fastest).}
#'   \item{classify(text, choices, system_prompt)}{Full classification with confidence scores.}
#'   \item{batch_generate(texts, choices, system_prompt)}{Batch constrained output.}
#'   \item{batch_classify(texts, choices, system_prompt)}{Batch classification.}
#' }
#'
#' @export
#' @examples
#' \dontrun{
#' classifier <- ollama_classifier("llama3.2")
#'
#' # Basic classification
#' result <- classify(
#'   classifier,
#'   text = "The goalkeeper made an incredible save!",
#'   choices = c("sports", "politics", "technology", "entertainment")
#' )
#' print(result$prediction)
#' print(result$confidence)
#'
#' # Generate only (fastest, no confidence)
#' prediction <- generate(
#'   classifier,
#'   text = "The team won the championship!",
#'   choices = c("sports", "finance", "politics")
#' )
#'
#' # With label descriptions
#' result <- classify(
#'   classifier,
#'   text = "The food was amazing but the service was terrible.",
#'   choices = list(
#'     positive = "Text expresses happiness, satisfaction, or approval",
#'     negative = "Text expresses anger, disappointment, or disapproval",
#'     mixed = "Text contains both positive and negative sentiments",
#'     neutral = "Text is factual without strong emotional content"
#'   )
#' )
#' }
ollama_classifier <- function(model, base_url = "http://localhost:11434") {
  labels <- get_choice_labels
  build_prompt <- build_classification_prompt
  schema <- build_json_schema
  forced <- build_forced_schema
  chat_fn <- ollama_chat
  extract_lp <- ollama_extract_logprob_sum
  softmax_fn <- stable_softmax

  # --- Generate ---
  generate_fn <- function(text, choices, system_prompt = NULL) {
    lbl <- labels(choices)
    prompt <- build_prompt(text, choices, system_prompt)
    s <- schema(lbl)

    resp <- chat_fn(
      base_url = base_url,
      model = model,
      messages = list(
        list(role = "system", content = prompt$system),
        list(role = "user", content = prompt$user)
      ),
      format = s,
      options = list(temperature = 0)
    )

    parsed <- jsonlite::fromJSON(resp$content, simplifyVector = FALSE)
    parsed$label %||% ""
  }

  # --- Classify (multi-call with softmax) ---
  get_logprob <- function(system, user, choice) {
    s <- forced(choice)
    resp <- chat_fn(
      base_url = base_url,
      model = model,
      messages = list(
        list(role = "system", content = system),
        list(role = "user", content = user)
      ),
      format = s,
      logprobs = TRUE,
      options = list(temperature = 0)
    )
    extract_lp(resp$logprobs)
  }

  classify_fn <- function(text, choices, system_prompt = NULL) {
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

  # --- Batch variants ---
  batch_generate_fn <- function(texts, choices, system_prompt = NULL) {
    purrr::map_chr(texts, ~ generate_fn(.x, choices, system_prompt))
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
    class = "ollama_classifier"
  )
}

#' @export
generate.ollama_classifier <- function(classifier, text, choices,
                                        system_prompt = NULL, ...) {
  classifier$generate(text, choices, system_prompt)
}

#' @export
classify.ollama_classifier <- function(classifier, text, choices,
                                       system_prompt = NULL, ...) {
  classifier$classify(text, choices, system_prompt)
}

#' @export
batch_generate.ollama_classifier <- function(classifier, texts, choices,
                                             system_prompt = NULL, ...) {
  classifier$batch_generate(texts, choices, system_prompt)
}

#' @export
batch_classify.ollama_classifier <- function(classifier, texts, choices,
                                              system_prompt = NULL, ...) {
  classifier$batch_classify(texts, choices, system_prompt)
}
