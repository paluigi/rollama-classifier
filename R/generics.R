#' Generate a constrained classification
#'
#' Generic for constrained output generation. Uses JSON schema with enum
#' constraint to ensure only valid choices are generated. This is the fastest
#' method as it only makes one API call and doesn't compute confidence scores.
#'
#' @param classifier A classifier object created by [ollama_classifier()] or
#'   [llm_classifier()].
#' @param text Character. The text to classify.
#' @param choices Either a character vector of labels or a named list mapping
#'   labels to descriptions.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @param ... Additional arguments (for future extensibility).
#'
#' @return Character. The predicted choice label.
#' @export
#' @examples
#' \dontrun{
#' classifier <- ollama_classifier("llama3.2")
#' prediction <- generate(
#'   classifier,
#'   text = "The team won the championship!",
#'   choices = c("sports", "finance", "politics")
#' )
#' }
generate <- function(classifier, text, choices, system_prompt = NULL, ...) {
  UseMethod("generate")
}

#' Score a classification using multi-call evaluation
#'
#' Makes separate API calls for each choice to compute log P(choice|context),
#' then applies softmax for calibrated probabilities. Makes N API calls for
#' N choices.
#'
#' @param classifier A classifier object.
#' @param text Character. The text to classify.
#' @param choices Either a character vector of labels or a named list.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @param ... Additional arguments.
#'
#' @return A [classification_result()] list.
#' @export
#' @examples
#' \dontrun{
#' classifier <- ollama_classifier("llama3.2")
#' result <- score(
#'   classifier,
#'   text = "The movie was fantastic!",
#'   choices = c("positive", "negative", "neutral")
#' )
#' }
score <- function(classifier, text, choices, system_prompt = NULL, ...) {
  UseMethod("score")
}

#' Classify text with calibrated confidence scores
#'
#' Alias for [score()] — uses multi-call evaluation to compute calibrated
#' probabilities for each choice.
#'
#' @param classifier A classifier object.
#' @param text Character. The text to classify.
#' @param choices Either a character vector of labels or a named list.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @param ... Additional arguments.
#'
#' @return A [classification_result()] list.
#' @export
#' @examples
#' \dontrun{
#' classifier <- ollama_classifier("llama3.2")
#' result <- classify(
#'   classifier,
#'   text = "I love this product!",
#'   choices = c("positive", "negative", "neutral")
#' )
#' print(result$prediction)
#' print(result$confidence)
#' }
classify <- function(classifier, text, choices, system_prompt = NULL, ...) {
  UseMethod("classify")
}

#' Batch constrained generation
#'
#' @param classifier A classifier object.
#' @param texts Character vector. Texts to classify.
#' @param choices Either a character vector of labels or a named list.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @param ... Additional arguments.
#'
#' @return Character vector of predicted labels.
#' @export
batch_generate <- function(classifier, texts, choices, system_prompt = NULL, ...) {
  UseMethod("batch_generate")
}

#' Batch scoring
#'
#' @param classifier A classifier object.
#' @param texts Character vector. Texts to classify.
#' @param choices Either a character vector of labels or a named list.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @param ... Additional arguments.
#'
#' @return A list of [classification_result()] objects.
#' @export
batch_score <- function(classifier, texts, choices, system_prompt = NULL, ...) {
  UseMethod("batch_score")
}

#' Batch classification
#'
#' @param classifier A classifier object.
#' @param texts Character vector. Texts to classify.
#' @param choices Either a character vector of labels or a named list.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @param ... Additional arguments.
#'
#' @return A list of [classification_result()] objects.
#' @export
batch_classify <- function(classifier, texts, choices, system_prompt = NULL, ...) {
  UseMethod("batch_classify")
}
