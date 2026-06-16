#' Ollama API Client Helpers
#'
#' Low-level functions for interacting with the Ollama REST API.
#'
#' @name ollama-api
#' @keywords internal
NULL

#' Send a chat completion request to Ollama
#'
#' @param base_url Character. Base URL of the Ollama server.
#' @param model Character. Model name.
#' @param messages List of message lists, each with `role` and `content`.
#' @param format List or `NULL`. Optional JSON schema for structured output.
#' @param logprobs Logical. Whether to return log probabilities.
#' @param options List. Additional model options (e.g. temperature).
#' @return List with `content` and optionally `logprobs`.
#' @keywords internal
ollama_chat <- function(base_url, model, messages, format = NULL,
                         logprobs = FALSE, options = NULL) {
  url <- httr2::url(paste0(base_url, "/api/chat"))

  body <- list(
    model = model,
    messages = messages,
    stream = FALSE
  )

  if (!is.null(format)) body$format <- format
  if (logprobs) body$options <- c(list(temperature = 0), options)

  req <- httr2::req_perform(
    httr2::req_body_json(
      httr2::req_url_post(url),
      body
    )
  )

  resp <- httr2::resp_body_json(req, simplifyVector = FALSE)

  content <- resp$message$content

  logprobs_out <- NULL
  if (logprobs && !is.null(resp$logprobs)) {
    # Ollama returns logprobs as a list of token objects
    logprobs_out <- resp$logprobs
  }

  list(content = content, logprobs = logprobs_out, raw = resp)
}

#' Extract logprob sum from Ollama response
#'
#' @param logprobs List of logprob objects from Ollama API response.
#' @return Numeric. Sum of log probabilities.
#' @keywords internal
ollama_extract_logprob_sum <- function(logprobs) {
  if (is.null(logprobs) || length(logprobs) == 0) return(0.0)
  sapply(logprobs, function(lp) {
    if (is.list(lp)) lp$logprob %||% 0.0 else lp
  }) |> sum()
}
