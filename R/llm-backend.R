#' LLM Backend Base Helpers
#'
#' Shared functionality for all OpenAI-compatible inference backends
#' (vLLM, SGLang, llama.cpp).
#'
#' @name llm-backend
#' @keywords internal
NULL

#' Build HTTP headers for API requests
#'
#' @param api_key Character. API key.
#' @return A named character vector of headers.
#' @keywords internal
build_headers <- function(api_key = "not-needed") {
  c(
    `Content-Type` = "application/json",
    Authorization = paste("Bearer", api_key)
  )
}

#' Build request body for OpenAI-compatible API
#'
#' @param model Character. Model identifier.
#' @param messages List of message lists.
#' @param temperature Numeric. Sampling temperature.
#' @param guided_json List or `NULL`. JSON schema for structured output.
#' @param logprobs Logical. Whether to return log probabilities.
#' @param top_logprobs Integer. Number of top log probs per token.
#' @param max_tokens Integer. Max tokens to generate.
#' @param extra_body List. Extra parameters to merge.
#' @return A list representing the request body.
#' @keywords internal
build_body <- function(model, messages, temperature = 0, guided_json = NULL,
                        logprobs = FALSE, top_logprobs = 5,
                        max_tokens = 256, extra_body = list()) {
  body <- list(
    model = model,
    messages = messages,
    temperature = temperature
  )

  if (!is.null(guided_json)) {
    body$guided_json <- guided_json
    body$response_format <- list(
      type = "json_schema",
      json_schema = list(
        name = "classification",
        schema = guided_json,
        strict = TRUE
      )
    )
  }

  if (logprobs) {
    body$logprobs <- TRUE
    body$top_logprobs <- top_logprobs
  }

  if (max_tokens > 0) body$max_tokens <- max_tokens

  # Merge extra_body last so it can override
  body <- purrr::list_modify(body, !!!extra_body)
  body
}

#' Parse response from OpenAI-compatible API
#'
#' @param data List. Parsed JSON response.
#' @return A list with `content`, `logprobs`, and `raw`.
#' @keywords internal
parse_response <- function(data) {
  choice <- data$choices[[1L]]
  content <- choice$message$content %||% ""

  logprobs_out <- NULL
  if (!is.null(choice$logprobs) && !is.null(choice$logprobs$content)) {
    logprobs_out <- purrr::map(choice$logprobs$content, function(tok) {
      list(
        token = tok$token,
        logprob = tok$logprob,
        top_logprobs = tok$top_logprobs %||% list()
      )
    })
  }

  list(content = content, logprobs = logprobs_out, raw = data)
}

#' Extract logprob sum from parsed response
#'
#' @param response List from [parse_response()].
#' @return Numeric. Sum of token log probabilities.
#' @keywords internal
extract_logprob_sum <- function(response) {
  if (is.null(response$logprobs) || length(response$logprobs) == 0) return(0.0)
  purrr::map_dbl(response$logprobs, "logprob", .default = 0) |> sum()
}

#' Send chat completion request to OpenAI-compatible server
#'
#' @param base_url Character. Base URL of the server.
#' @param api_key Character. API key.
#' @param timeout Numeric. Request timeout in seconds.
#' @param body List. Request body.
#' @return Parsed response list.
#' @keywords internal
send_chat_request <- function(base_url, api_key, timeout, body) {
  url <- httr2::url(paste0(base_url, "/chat/completions"))

  req <- httr2::req_url_post(url) |>
    httr2::req_headers(!!!build_headers(api_key)) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout)

  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp, simplifyVector = FALSE) |>
    parse_response()
}
