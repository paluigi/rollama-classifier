#' Ollama API Client Helpers
#'
#' Low-level functions for interacting with the Ollama REST API (native
#' endpoints: /api/chat, /api/generate, /api/tokenize).
#'
#' @name ollama-api
#' @keywords internal
NULL


#' Build JSON enum schema for label constraint
#'
#' @param labels Character vector of valid labels.
#' @return A list representing a JSON schema with enum constraint.
#' @keywords internal
build_json_enum <- function(labels) {
  list(
    type = "object",
    properties = list(
      label = list(type = "string", enum = as.list(labels))
    ),
    required = list("label")
  )
}


#' The JSON prefix that precedes the label in Ollama responses
#'
#' Used for context-dependent tokenization so the trie matches the actual
#' response tokens.
#' @keywords internal
OLLAMA_JSON_LABEL_CONTEXT <- '{"label": "'


#' Send a chat completion request to Ollama
#'
#' Uses the native `/api/chat` endpoint. When `constrain_labels` is provided,
#' builds a JSON enum schema and passes it via the `format` parameter.
#'
#' @param base_url Character. Base URL of the Ollama server.
#' @param model Character. Model name.
#' @param messages List of message lists, each with `role` and `content`.
#' @param constrain_labels Character vector or `NULL`. Labels to constrain output to.
#' @param logprobs Logical. Whether to return log probabilities.
#' @param top_logprobs Integer or `NULL`. Number of top alternatives per token.
#' @param options List. Additional model options.
#' @return A list with `content`, `label`, `logprobs`, and `raw`.
#' @keywords internal
ollama_chat <- function(base_url, model, messages, constrain_labels = NULL,
                        logprobs = FALSE, top_logprobs = NULL, options = NULL) {
  fmt <- NULL
  if (!is.null(constrain_labels)) {
    fmt <- build_json_enum(constrain_labels)
  }

  body <- list(
    model = model,
    messages = messages,
    stream = FALSE
  )
  if (!is.null(fmt)) body$format <- fmt
  if (logprobs) {
    body$logprobs <- TRUE
    if (!is.null(top_logprobs)) body$top_logprobs <- top_logprobs
  }

  opts <- c(list(temperature = 0), options %||% list())
  body$options <- opts

  req <- httr2::request(paste0(base_url, "/api/chat")) |>
    httr2::req_method("POST") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()

  resp <- httr2::resp_body_json(req, simplifyVector = FALSE)

  content <- resp$message$content
  label <- content
  # Try to extract label from JSON
  parsed <- tryCatch(
    jsonlite::fromJSON(content, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(parsed) && !is.null(parsed$label)) {
    label <- parsed$label
  }

  # Parse logprobs into flat structure
  logprobs_out <- NULL
  if (logprobs && !is.null(resp$logprobs)) {
    logprobs_out <- purrr::map(resp$logprobs, function(lp) {
      top <- list()
      if (!is.null(lp$top_logprobs)) {
        for (alt in lp$top_logprobs) {
          top[[alt$token]] <- alt$logprob
        }
      }
      list(
        token = lp$token %||% "",
        logprob = lp$logprob %||% 0.0,
        top_logprobs = top
      )
    })
  }

  list(content = content, label = label, logprobs = logprobs_out, raw = resp)
}


#' Score a completion using Ollama's generate endpoint with suffix
#'
#' Uses `/api/generate` with `suffix=completion` to compute per-token logprobs
#' of the completion given the prompt context. No generation occurs
#' (`num_predict = 0`).
#'
#' @param base_url Character. Base URL of the Ollama server.
#' @param model Character. Model name.
#' @param messages List of message lists.
#' @param completion Character. The completion text to score.
#' @param options List. Additional options.
#' @return A list with `completion` and `logprobs`.
#' @keywords internal
ollama_score <- function(base_url, model, messages, completion, options = NULL) {
  prompt <- purrr::keep(messages, ~ .x$role %in% c("system", "user")) |>
    purrr::map_chr("content") |>
    paste(collapse = "\n\n")

  body <- list(
    model = model,
    prompt = prompt,
    suffix = completion,
    stream = FALSE,
    logprobs = TRUE,
    options = c(list(temperature = 0, num_predict = 0), options %||% list())
  )

  req <- httr2::request(paste0(base_url, "/api/generate")) |>
    httr2::req_method("POST") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()

  resp <- httr2::resp_body_json(req, simplifyVector = FALSE)

  logprobs_out <- list()
  if (!is.null(resp$logprobs)) {
    logprobs_out <- purrr::map(resp$logprobs, function(lp) {
      top <- list()
      if (!is.null(lp$top_logprobs)) {
        for (alt in lp$top_logprobs) {
          top[[alt$token]] <- alt$logprob
        }
      }
      list(
        token = lp$token %||% "",
        logprob = lp$logprob %||% 0.0,
        top_logprobs = top
      )
    })
  }

  list(completion = completion, logprobs = logprobs_out, raw = resp)
}


#' Tokenize text using Ollama's tokenize API
#'
#' If `context` is provided, tokenizes `context + text` and returns only the
#' tokens corresponding to `text` (context-dependent tokenization).
#'
#' @param base_url Character. Base URL of the Ollama server.
#' @param model Character. Model name.
#' @param text Character. The text to tokenize.
#' @param context Character or `NULL`. Prefix for context-dependent tokenization.
#' @return Character vector of token strings (or IDs as strings).
#' @keywords internal
ollama_tokenize <- function(base_url, model, text, context = NULL) {
  full_text <- paste0(context %||% "", text)

  body <- list(model = model, text = full_text)
  req <- httr2::request(paste0(base_url, "/api/tokenize")) |>
    httr2::req_method("POST") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()

  resp <- httr2::resp_body_json(req, simplifyVector = FALSE)
  tokens <- resp$tokens %||% integer(0)

  if (!is.null(context)) {
    ctx_body <- list(model = model, text = context)
    ctx_req <- httr2::request(paste0(base_url, "/api/tokenize")) |>
      httr2::req_method("POST") |>
      httr2::req_body_json(ctx_body) |>
      httr2::req_perform()

    ctx_resp <- httr2::resp_body_json(ctx_req, simplifyVector = FALSE)
    ctx_len <- length(ctx_resp$tokens %||% integer(0))
    if (ctx_len > 0 && ctx_len < length(tokens)) {
      tokens <- tokens[(ctx_len + 1):length(tokens)]
    }
  }

  # Return token IDs as character strings (Ollama returns integer IDs)
  as.character(tokens)
}
