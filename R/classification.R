#' Classification Result
#'
#' @description
#' Result of a classification operation. Returned by [classify()], [score()],
#' and their batch variants.
#'
#' @param prediction Character. The predicted class label.
#' @param confidence Numeric between 0 and 1. Confidence score for the
#'   prediction.
#' @param probabilities Named numeric vector. Probability distribution over
#'   all choices (sums to 1).
#' @param raw_response List. Raw response from the API for debugging.
#'   May be a list with `logprobs` or the raw API response.
#'
#' @return A list of class `classification_result` with components:
#' \describe{
#'   \item{prediction}{Character. The predicted label.}
#'   \item{confidence}{Numeric. Confidence score (0-1).}
#'   \item{probabilities}{Named numeric vector. Probability distribution.}
#'   \item{raw_response}{List. Raw API response for debugging.}
#' }
#'
#' @export
#' @examples
#' res <- classification_result(
#'   prediction = "positive",
#'   confidence = 0.85,
#'   probabilities = c(positive = 0.85, negative = 0.10, neutral = 0.05),
#'   raw_response = list()
#' )
#' print(res$prediction)
classification_result <- function(prediction, confidence, probabilities, raw_response = list()) {
  structure(
    list(
      prediction = prediction,
      confidence = confidence,
      probabilities = probabilities,
      raw_response = raw_response
    ),
    class = "classification_result"
  )
}

#' @export
print.classification_result <- function(x, ...) {
  cat("ClassificationResult\n")
  cat("  Prediction:   ", x$prediction, "\n", sep = "")
  cat("  Confidence:    ", sprintf("%.2f%%", x$confidence * 100), "\n", sep = "")
  cat("  Probabilities: ", sep = "")
  probs <- x$probabilities
  if (length(probs) > 0) {
    prob_str <- paste0(
      names(probs), "=",
      sprintf("%.2f%%", probs * 100),
      collapse = ", "
    )
    cat(prob_str, "\n")
  }
  invisible(x)
}

#' Format choices for prompt
#'
#' @param choices Either a character vector of labels or a named list
#'   mapping labels to descriptions.
#' @return A single string with formatted choices.
#' @keywords internal
format_choices <- function(choices) {
  if (is.list(choices) && !is.null(names(choices))) {
    choices |>
      purrr::imap_chr(~ paste0("- ", .y, ": ", .x)) |>
      paste(collapse = "\n")
  } else {
    choices |>
      purrr::map_chr(~ paste0("- ", .x)) |>
      paste(collapse = "\n")
  }
}

#' Extract choice labels from either format
#'
#' @param choices Either a character vector of labels or a named list.
#' @return Character vector of labels.
#' @export
#' @examples
#' get_choice_labels(c("a", "b", "c"))
#' get_choice_labels(list(positive = "Happy", negative = "Sad"))
get_choice_labels <- function(choices) {
  if (is.list(choices) && !is.null(names(choices))) {
    names(choices)
  } else {
    as.character(choices)
  }
}

#' Build JSON schema for constrained output
#'
#' @param labels Character vector of valid labels.
#' @return A list representing a JSON schema.
#' @keywords internal
build_json_schema <- function(labels) {
  list(
    type = "object",
    properties = list(
      label = list(
        type = "string",
        `enum` = as.list(labels)
      )
    ),
    required = list("label")
  )
}

#' Build forced-choice JSON schema for a single label
#'
#' @param choice Character. The choice label to force.
#' @return A list representing a JSON schema with a single enum value.
#' @keywords internal
build_forced_schema <- function(choice) {
  list(
    type = "object",
    properties = list(
      label = list(
        type = "string",
        `enum` = list(choice)
      )
    ),
    required = list("label")
  )
}

#' Build the system and user prompts for classification
#'
#' @param text Character. The text to classify.
#' @param choices Either a character vector of labels or a named list.
#' @param system_prompt Character or `NULL`. Optional custom system prompt.
#' @return A list with components `system` and `user`.
#' @export
#' @examples
#' build_classification_prompt(
#'   "I love this!",
#'   c("positive", "negative", "neutral")
#' )
build_classification_prompt <- function(text, choices, system_prompt = NULL) {
  choices_text <- format_choices(choices)

  if (is.null(system_prompt)) {
    system_prompt <- paste(
      "You are a precise text classifier.",
      "Your task is to classify the given text into exactly one of the provided categories.",
      "Respond with only the category label, nothing else."
    )
  }

  user_prompt <- paste0(
    "Classify the following text into one of these categories:\n\n",
    choices_text, "\n\n",
    "Text to classify:\n",
    text, "\n\n",
    "Respond with only the category label."
  )

  list(system = system_prompt, user = user_prompt)
}

#' Numerically stable softmax
#'
#' @param logprobs Named numeric vector of log probabilities.
#' @return Named numeric vector of probabilities summing to 1.
#' @keywords internal
stable_softmax <- function(logprobs) {
  valid <- logprobs[logprobs > -Inf]

  if (length(valid) == 0) {
    n <- length(logprobs)
    probs <- rep(1 / n, n)
    names(probs) <- names(logprobs)
    return(probs)
  }

  max_lp <- max(valid)
  exp_vals <- ifelse(logprobs > -Inf, exp(logprobs - max_lp), 0)
  total <- sum(exp_vals)

  if (total == 0) {
    n <- length(logprobs)
    probs <- rep(1 / n, n)
    names(probs) <- names(logprobs)
    return(probs)
  }

  probs <- exp_vals / total
  names(probs) <- names(logprobs)
  probs
}
