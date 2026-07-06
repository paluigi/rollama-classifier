#' Inference backends for rollama
#'
#' Each backend provides a unified interface with `chat()`, `score()`, and
#' `tokenize()` methods, plus a `supports_bare_label_constraint` capability
#' flag. Backends communicate via HTTP using the OpenAI-compatible API
#' (vLLM, SGLang, llama.cpp) or the native API (Ollama).
#'
#' @name backends
NULL


# =========================================================================
# Shared helpers for OpenAI-compatible backends
# =========================================================================

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

#' Build base OpenAI-compatible request body
#'
#' @param model Character. Model identifier.
#' @param messages List of message lists.
#' @param temperature Numeric. Sampling temperature.
#' @param logprobs Logical. Whether to return log probabilities.
#' @param top_logprobs Integer. Number of top log probs per token.
#' @param max_tokens Integer. Max tokens to generate.
#' @param extra_body List. Extra parameters to merge.
#' @return A list representing the request body.
#' @keywords internal
build_omni_body <- function(model, messages, temperature = 0, logprobs = FALSE,
                             top_logprobs = 5, max_tokens = 256, extra_body = list()) {
  body <- list(
    model = model,
    messages = purrr::map(messages, ~ list(role = .x$role, content = .x$content)),
    temperature = temperature,
    max_tokens = max_tokens
  )
  if (logprobs) {
    body$logprobs <- TRUE
    body$top_logprobs <- top_logprobs
  }
  purrr::list_modify(body, !!!extra_body)
}

#' Render messages to a plain text prompt for completions endpoint
#'
#' @param messages List of message lists with `role` and `content`.
#' @return Character string.
#' @keywords internal
render_prompt <- function(messages) {
  parts <- purrr::map(messages, function(m) {
    if (m$role == "system") paste0("<|system|>\n", m$content)
    else if (m$role == "user") paste0("<|user|>\n", m$content)
    else ""
  })
  paste(parts, collapse = "\n\n") |>
    paste0("\n\n<|assistant|>\n")
}

#' Parse OpenAI-compatible chat response
#'
#' @param data List. Parsed JSON response.
#' @return A list with `content`, `label`, `logprobs`, and `raw`.
#' @keywords internal
parse_omni_response <- function(data) {
  choice <- data$choices[[1L]]
  content <- choice$message$content %||% ""

  logprobs_out <- NULL
  if (!is.null(choice$logprobs) && !is.null(choice$logprobs$content)) {
    logprobs_out <- purrr::map(choice$logprobs$content, function(tok) {
      top <- list()
      for (alt in (tok$top_logprobs %||% list())) {
        top[[alt$token]] <- alt$logprob
      }
      list(
        token = tok$token,
        logprob = tok$logprob,
        top_logprobs = top
      )
    })
  }

  list(content = content, label = content, logprobs = logprobs_out, raw = data)
}

#' Send chat completion request to OpenAI-compatible server
#'
#' @param base_url Character. Base URL.
#' @param api_key Character. API key.
#' @param timeout Numeric. Timeout in seconds.
#' @param body List. Request body.
#' @return Parsed response list.
#' @keywords internal
send_omni_chat <- function(base_url, api_key, timeout, body) {
  req <- httr2::request(paste0(base_url, "/chat/completions")) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!build_headers(api_key)) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout) |>
    httr2::req_perform()

  httr2::resp_body_json(req, simplifyVector = FALSE) |>
    parse_omni_response()
}

#' Score a completion via OpenAI-compatible completions endpoint
#'
#' @param base_url Character.
#' @param api_key Character.
#' @param timeout Numeric.
#' @param model Character.
#' @param messages List.
#' @param completion Character.
#' @param extra_body List.
#' @return A list with `completion` and `logprobs`.
#' @keywords internal
omni_score <- function(base_url, api_key, timeout, model, messages, completion,
                        extra_body = list()) {
  prompt <- render_prompt(messages)
  body <- list(
    model = model,
    prompt = paste0(prompt, completion),
    echo = TRUE,
    max_tokens = 1,
    temperature = 0,
    logprobs = 1
  )
  body <- purrr::list_modify(body, !!!extra_body)

  req <- httr2::request(paste0(base_url, "/completions")) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!build_headers(api_key)) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout) |>
    httr2::req_perform()

  data <- httr2::resp_body_json(req, simplifyVector = FALSE)
  choice <- data$choices[[1]]
  all_lp <- choice$logprobs %||% list()

  tokens_list <- all_lp$tokens %||% list()
  token_lps_list <- all_lp$token_logprobs %||% list()
  top_lps_list <- all_lp$top_logprobs %||% list()

  # Find completion start by counting prompt tokens
  prompt_n <- omni_tokenize_count(base_url, api_key, timeout, model, prompt)

  logprobs_out <- list()
  if (length(tokens_list) > prompt_n) {
    for (i in seq(prompt_n + 1L, length(tokens_list))) {
      top <- list()
      if (i <= length(top_lps_list) && !is.null(top_lps_list[[i]])) {
        for (tok in names(top_lps_list[[i]])) {
          top[[tok]] <- top_lps_list[[i]][[tok]]
        }
      }
      lp <- if (i <= length(token_lps_list)) token_lps_list[[i]] else 0.0
      logprobs_out <- c(logprobs_out, list(list(
        token = tokens_list[[i]],
        logprob = lp %||% 0.0,
        top_logprobs = top
      )))
    }
  }

  list(completion = completion, logprobs = logprobs_out, raw = data)
}

#' Count tokens via OpenAI-compatible tokenize endpoint
#' @keywords internal
omni_tokenize_count <- function(base_url, api_key, timeout, model, text) {
  tryCatch({
    body <- list(model = model, prompt = text)
    req <- httr2::request(paste0(base_url, "/tokenize")) |>
      httr2::req_method("POST") |>
      httr2::req_headers(!!!build_headers(api_key)) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(timeout) |>
      httr2::req_perform()
    length(httr2::resp_body_json(req, simplifyVector = FALSE)$tokens %||% list())
  }, error = function(e) 0L)
}

#' Tokenize via OpenAI-compatible endpoint
#' @keywords internal
omni_tokenize <- function(base_url, api_key, timeout, model, text, context = NULL) {
  full_text <- paste0(context %||% "", text)
  body <- list(model = model, prompt = full_text)
  req <- httr2::request(paste0(base_url, "/tokenize")) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!build_headers(api_key)) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout) |>
    httr2::req_perform()

  data <- httr2::resp_body_json(req, simplifyVector = FALSE)
  tokens <- data$tokens %||% integer(0)

  if (!is.null(context)) {
    ctx_n <- omni_tokenize_count(base_url, api_key, timeout, model, context)
    if (ctx_n > 0 && ctx_n < length(tokens)) {
      tokens <- tokens[(ctx_n + 1):length(tokens)]
    }
  }

  as.character(tokens)
}


# =========================================================================
# Ollama Backend
# =========================================================================

#' Ollama Backend
#'
#' @description
#' Backend for the Ollama runtime (>=v0.12) via the native Ollama REST API.
#'
#' Ollama uses JSON Schema enum for label constraints. The model generates
#' `{"label": "<chosen>"}`. Structural JSON tokens are filtered during trie
#' reconstruction. Context-dependent tokenization ensures the trie matches
#' the actual response tokens.
#'
#' @param model Character. Model name (e.g., `"llama3.2"`).
#' @param host Character. Ollama server URL. Defaults to
#'   `"http://localhost:11434"`.
#' @param timeout Numeric. Request timeout in seconds.
#' @param max_tokens Integer. Max tokens to generate.
#' @param extra_body List. Extra parameters for options.
#' @return A backend list with `chat()`, `score()`, `tokenize()`, and
#'   capability flags.
#' @export
#' @examples
#' \dontrun{
#' backend <- ollama_backend("llama3.2")
#' classifier <- llm_classifier(backend)
#' }
ollama_backend <- function(model, host = "http://localhost:11434",
                            timeout = 120, max_tokens = 256, extra_body = list()) {
  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    ollama_chat(
      base_url = host, model = model, messages = messages,
      constrain_labels = constrain_labels,
      logprobs = logprobs, top_logprobs = top_logprobs,
      options = c(list(num_predict = max_tokens), extra_body)
    )
  }

  score_fn <- function(messages, completion) {
    ollama_score(host, model, messages, completion, extra_body)
  }

  tokenize_fn <- function(text, context = NULL) {
    ollama_tokenize(host, model, text, context)
  }

  structure(
    list(
      chat = chat_fn,
      score = score_fn,
      tokenize = tokenize_fn,
      model = model,
      base_url = host,
      supports_bare_label_constraint = FALSE
    ),
    class = c("ollama_backend", "llm_backend")
  )
}


# =========================================================================
# vLLM Backend
# =========================================================================

#' vLLM Backend
#'
#' @description
#' Backend for the vLLM inference server. vLLM provides a high-throughput
#' serving engine with an OpenAI-compatible API. It supports `guided_choice`
#' natively, generating bare label text with no JSON wrapper.
#'
#' @param model Character. Model identifier.
#' @param base_url Character. Base URL of the vLLM server.
#' @param api_key Character. API key.
#' @param timeout Numeric. Request timeout in seconds.
#' @param max_tokens Integer. Max tokens to generate.
#' @param extra_body List. Extra parameters merged into every request.
#' @return A backend list.
#' @export
#' @examples
#' \dontrun{
#' backend <- vllm_backend("meta-llama/Llama-3.2-3B-Instruct")
#' }
vllm_backend <- function(model, base_url = "http://localhost:8000/v1",
                          api_key = "not-needed", timeout = 120,
                          max_tokens = 256, extra_body = list()) {
  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- build_omni_body(model, messages, temperature, logprobs, top_logprobs,
                             max_tokens, extra_body)
    if (!is.null(constrain_labels)) body$guided_choice <- constrain_labels
    send_omni_chat(base_url, api_key, timeout, body)
  }

  score_fn <- function(messages, completion) {
    omni_score(base_url, api_key, timeout, model, messages, completion, extra_body)
  }

  tokenize_fn <- function(text, context = NULL) {
    omni_tokenize(base_url, api_key, timeout, model, text, context)
  }

  structure(
    list(
      chat = chat_fn, score = score_fn, tokenize = tokenize_fn,
      model = model, base_url = base_url,
      supports_bare_label_constraint = TRUE
    ),
    class = c("vllm_backend", "llm_backend")
  )
}


# =========================================================================
# SGLang Backend
# =========================================================================

#' SGLang Backend
#'
#' @description
#' Backend for the SGLang inference server. Uses regex constraint for
#' bare-label generation.
#'
#' @inheritParams vllm_backend
#' @return A backend list.
#' @export
#' @examples
#' \dontrun{
#' backend <- sglang_backend("meta-llama/Llama-3.2-3B-Instruct")
#' }
sglang_backend <- function(model, base_url = "http://localhost:30000/v1",
                            api_key = "not-needed", timeout = 120,
                            max_tokens = 256, extra_body = list()) {
  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- build_omni_body(model, messages, temperature, logprobs, top_logprobs,
                             max_tokens, extra_body)
    if (!is.null(constrain_labels)) {
      escaped <- purrr::map_chr(constrain_labels, ~ gsub("([\\[\\]{}.|*+?()^$])", "\\\\\\1", .x))
      body$regex <- paste0("(", paste(escaped, collapse = "|"), ")")
    }
    send_omni_chat(base_url, api_key, timeout, body)
  }

  score_fn <- function(messages, completion) {
    omni_score(base_url, api_key, timeout, model, messages, completion, extra_body)
  }

  tokenize_fn <- function(text, context = NULL) {
    omni_tokenize(base_url, api_key, timeout, model, text, context)
  }

  structure(
    list(
      chat = chat_fn, score = score_fn, tokenize = tokenize_fn,
      model = model, base_url = base_url,
      supports_bare_label_constraint = TRUE
    ),
    class = c("sglang_backend", "llm_backend")
  )
}


# =========================================================================
# llama.cpp Backend
# =========================================================================

#' llama.cpp Backend
#'
#' @description
#' Backend for the llama.cpp server (`llama-server`). Uses GBNF grammar for
#' bare-label generation, producing clean label text with no JSON wrapper.
#'
#' @inheritParams vllm_backend
#' @return A backend list.
#' @export
#' @examples
#' \dontrun{
#' backend <- llamacpp_backend("model")
#' }
llamacpp_backend <- function(model, base_url = "http://localhost:8080/v1",
                               api_key = "not-needed", timeout = 120,
                               max_tokens = 256, extra_body = list()) {
  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- build_omni_body(model, messages, temperature, logprobs, top_logprobs,
                             max_tokens, extra_body)
    if (!is.null(constrain_labels)) {
      # Build GBNF grammar: root ::= "label1" | "label2" | "label3"
      quoted <- purrr::map_chr(constrain_labels, ~ paste0('"', .x, '"'))
      body$grammar <- paste0("root ::= ", paste(quoted, collapse = " | "))
    }
    send_omni_chat(base_url, api_key, timeout, body)
  }

  score_fn <- function(messages, completion) {
    omni_score(base_url, api_key, timeout, model, messages, completion, extra_body)
  }

  tokenize_fn <- function(text, context = NULL) {
    omni_tokenize(base_url, api_key, timeout, model, text, context)
  }

  structure(
    list(
      chat = chat_fn, score = score_fn, tokenize = tokenize_fn,
      model = model, base_url = base_url,
      supports_bare_label_constraint = TRUE
    ),
    class = c("llamacpp_backend", "llm_backend")
  )
}
