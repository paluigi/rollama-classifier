#' Ollama API Client Helpers
#'
#' Low-level functions for interacting with the Ollama REST API (native
#' `/api/chat` endpoint).
#'
#' Modern Ollama (>=v0.12) removed the `/api/tokenize` endpoint and does not
#' support fill-in-the-middle ("insert") on instruct models. This module
#' therefore obtains both label tokenization and completion scores through
#' *empirical forced constrained generation*: it forces a label as the only
#' valid choice in a `chat()` call and reads back the model's genuine
#' per-token logprobs. No `/api/tokenize` or `suffix`/insert calls are used.
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


#' Extract label-value tokens from a JSON-enum constrained response
#'
#' Extracts the label-value tokens (with their logprobs) from a
#' `{"label": "<label>"}` constrained response.
#'
#' Robust to model-specific whitespace in the emitted JSON. The returned
#' tokens keep their *exact* emitted strings so they match the tokens the
#' model produces during multi-label constrained generation in `generate()`.
#'
#' Primary strategy: reconstruct the full emitted string, locate the value
#' span after the JSON `:` separator, and map that character span back to
#' token indices. Falls back to JSON-skeleton filtering if the span mapping
#' yields nothing.
#'
#' @param logprobs List of logprob entries, each with `token`, `logprob`,
#'   and `top_logprobs`.
#' @param label Character. The label text to locate.
#' @return A filtered list of logprob entries (only the label-value tokens).
#' @keywords internal
ollama_label_token_logprobs <- function(logprobs, label) {
  if (length(logprobs) == 0) return(list())

  # Reconstruct the full emitted string
  full <- paste(purrr::map_chr(logprobs, "token"), collapse = "")

  # ---- Primary: character-offset span mapping ----
  span_result <- tryCatch({
    colon <- base::regexpr(":", full, fixed = TRUE)[1]
    if (colon < 0) stop("no colon")
    # Search for label after the colon
    after_colon <- substr(full, colon + 1, nchar(full))
    label_start_rel <- base::regexpr(
      gsub("([.\\\\\\[\\](){}*+?^$|])", "\\\\\\1", label, perl = TRUE),
      after_colon, perl = TRUE
    )[1]
    if (label_start_rel < 0) stop("label not found")
    vstart <- colon + label_start_rel
    vend <- vstart + nchar(label)

    # Map char span to token indices
    out <- list()
    pos <- 1  # R is 1-based
    for (lp in logprobs) {
      tok_len <- nchar(lp$token)
      tok_end <- pos + tok_len - 1
      if (tok_end >= vstart && pos < vend) {
        out <- c(out, list(lp))
      }
      pos <- pos + tok_len
    }
    if (length(out) > 0) out else stop("empty span")
  }, error = function(e) NULL)

  if (!is.null(span_result)) return(span_result)

  # ---- Fallback: drop pure JSON-structure tokens / the "label" key ----
  out <- list()
  for (lp in logprobs) {
    stripped <- trimws(lp$token)
    cleaned <- gsub('["{}: \t\n]', "", stripped)
    if (cleaned == "" || stripped == "label") next
    out <- c(out, list(lp))
  }
  out
}


#' Score a completion by forcing it as the single valid label
#'
#' Modern Ollama (and instruct models in general) do not support the
#' fill-in-the-middle ("insert") mode that `/api/generate` with `suffix=`
#' requires. Instead, this forces `completion` as the only valid label via
#' a JSON-enum constrained `chat()` call and reads back the model's genuine
#' per-token logprobs (teacher forcing). No free generation occurs beyond
#' the forced label.
#'
#' @param base_url Character. Base URL of the Ollama server.
#' @param model Character. Model name.
#' @param messages List of message lists.
#' @param completion Character. The completion text to score.
#' @param extra_body List. Extra parameters for options.
#' @param token_cache Environment. Memoization cache for tokenize (shared).
#' @return A list with `completion` and `logprobs`.
#' @keywords internal
ollama_score <- function(base_url, model, messages, completion,
                         extra_body = list(), token_cache = NULL) {
  options <- c(list(num_predict = 256), extra_body)

  response <- ollama_chat(
    base_url = base_url,
    model = model,
    messages = messages,
    constrain_labels = completion,
    logprobs = TRUE,
    top_logprobs = 1,
    options = options
  )

  lps <- ollama_label_token_logprobs(response$logprobs %||% list(), completion)
  if (length(lps) == 0) {
    stop(sprintf("score(%s): forced generation returned no value tokens",
                 deparse(completion)), call. = FALSE)
  }

  list(completion = completion, logprobs = lps, raw = response$raw)
}


#' Tokenize text via empirical forced generation
#'
#' Modern Ollama removed the `/api/tokenize` endpoint (and the SDK no
#' longer exposes a `tokenize` method). To get the *exact* token strings
#' the model emits for `text` inside the JSON wrapper, this forces `text`
#' as the only valid label in a constrained `chat()` call and reads back
#' the emitted value tokens. Results are memoized per label.
#'
#' The `context` argument is accepted for interface compatibility but
#' ignored: Ollama always wraps the label in the constant JSON prefix
#' (double-quote-brace-label-colon-space-double-quote) regardless of
#' surrounding prompt tokens.
#'
#' @param base_url Character. Base URL of the Ollama server.
#' @param model Character. Model name.
#' @param text Character. The text to tokenize.
#' @param context Character or `NULL`. Ignored (accepted for interface compat).
#' @param token_cache Environment. Memoization cache.
#' @return Character vector of token strings.
#' @keywords internal
ollama_tokenize <- function(base_url, model, text, context = NULL,
                            token_cache = NULL) {
  # Check cache
  if (!is.null(token_cache) && !is.null(token_cache[[text]])) {
    return(token_cache[[text]])
  }

  response <- ollama_chat(
    base_url = base_url,
    model = model,
    messages = list(list(role = "user", content = text)),
    constrain_labels = text,
    logprobs = TRUE,
    top_logprobs = 1
  )

  lps <- ollama_label_token_logprobs(response$logprobs %||% list(), text)
  tokens <- purrr::map_chr(lps, "token")
  if (length(tokens) == 0) tokens <- text

  # Memoize
  if (!is.null(token_cache)) {
    token_cache[[text]] <- tokens
  }

  tokens
}
