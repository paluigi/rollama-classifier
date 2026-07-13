#' Inference backends for rollama
#'
#' Each backend provides a unified interface with `chat()`, `score()`, and
#' `tokenize()` methods, plus a `supports_bare_label_constraint` capability
#' flag. Backends communicate via HTTP using the OpenAI-compatible API
#' (vLLM, SGLang, llama.cpp) or the native API (Ollama).
#'
#' @name backends
#' @keywords internal
NULL


# =========================================================================
# Shared helpers for OpenAI-compatible backends
# =========================================================================

#' End-of-sequence / special tokens to filter from constrained responses
#'
#' Covers Llama-3, Phi, and Qwen EOS markers.
#' @keywords internal
SPECIAL_TOKENS <- c(
  "<|im_end|>",
  "<|endoftext|>",
  "</s>",
  "<|end_of_turn|>",
  "<|eot_id|>",
  "<|end|>",
  "<|eom_id|>"
)

#' Filter out special / end-of-sequence tokens from a logprobs list
#'
#' For bare-label backends (vLLM, SGLang, llama.cpp), the constraint
#' guarantees only label text is generated, so we just need to remove
#' special/EOS tokens and empty strings.
#'
#' @param logprobs List of logprob entries with `token`, `logprob`,
#'   `top_logprobs`.
#' @return Filtered list of logprob entries.
#' @keywords internal
filter_special_tokens <- function(logprobs) {
  purrr::keep(logprobs, ~ {
    tok <- .x$token
    !is.null(tok) && nzchar(trimws(tok)) && !(tok %in% SPECIAL_TOKENS)
  })
}

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

#' Count tokens via OpenAI-compatible tokenize endpoint
#'
#' Uses the correct `"prompt"` field name for the `/tokenize` endpoint.
#' Raises on HTTP errors — no silent masking.
#'
#' @param base_url Character. Base URL (with `/v1`).
#' @param api_key Character. API key.
#' @param timeout Numeric. Timeout in seconds.
#' @param model Character. Model name.
#' @param text Character. Text to tokenize.
#' @return Integer. Number of tokens.
#' @keywords internal
omni_tokenize_count <- function(base_url, api_key, timeout, model, text) {
  body <- list(model = model, prompt = text)
  req <- httr2::request(paste0(base_url, "/tokenize")) |>
    httr2::req_method("POST") |>
    httr2::req_headers(!!!build_headers(api_key)) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(timeout) |>
    httr2::req_perform()

  data <- httr2::resp_body_json(req, simplifyVector = FALSE)
  length(data$tokens %||% list())
}

#' Strip the `/v1` suffix to get the server base URL (for `/tokenize`)
#'
#' @param base_url Character. Base URL with `/v1`.
#' @return Character. Base URL without `/v1`.
#' @keywords internal
server_url <- function(base_url) {
  url <- sub("/+$", "", base_url)
  sub("/v1$", "", url)
}

#' Score a completion via echo/prefill logprobs (vLLM, SGLang)
#'
#' Uses `/v1/completions` with `echo=TRUE` to recover the model's genuine
#' per-token logprobs for the label as an unexpected continuation of the
#' prompt. The `/tokenize` endpoint pinpoints the exact label-token boundary.
#' The spurious `max_tokens=1` generated token is discarded by slicing to
#' `total_len`.
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
  prompt_with_completion <- paste0(prompt, completion)

  surl <- server_url(base_url)

  prompt_len <- omni_tokenize_count(surl, api_key, timeout, model, prompt)
  total_len <- omni_tokenize_count(surl, api_key, timeout, model, prompt_with_completion)

  body <- list(
    model = model,
    prompt = prompt_with_completion,
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

  # Slice to completion tokens (R is 1-based: prompt_len+1 .. total_len)
  if (total_len > prompt_len) {
    idx <- seq(prompt_len + 1L, total_len)
  } else {
    idx <- integer(0)
  }

  completion_tokens <- if (length(idx) > 0) tokens_list[idx] else list()
  completion_lps <- if (length(idx) > 0) token_lps_list[idx] else list()
  completion_top <- if (length(idx) > 0) top_lps_list[idx] else list()

  logprobs_out <- list()
  for (i in seq_along(completion_tokens)) {
    top <- list()
    if (i <= length(completion_top) && !is.null(completion_top[[i]])) {
      for (tok in names(completion_top[[i]])) {
        top[[tok]] <- completion_top[[i]][[tok]]
      }
    }
    lp <- if (i <= length(completion_lps)) completion_lps[[i]] else 0.0
    logprobs_out <- c(logprobs_out, list(list(
      token = completion_tokens[[i]],
      logprob = lp %||% 0.0,
      top_logprobs = top
    )))
  }

  if (length(logprobs_out) == 0) {
    stop(sprintf("score(%s): echo returned no label tokens",
                 deparse(completion)), call. = FALSE)
  }

  list(completion = completion, logprobs = logprobs_out, raw = data)
}

#' Score a completion via forced constrained generation (llama.cpp)
#'
#' Forces `completion` as the only valid choice via the backend's constraint
#' mechanism and reads back the model's genuine per-token logprobs
#' (teacher forcing, pre-mask). Used by backends that do not support
#' `echo=TRUE` on the completions endpoint (llama.cpp).
#'
#' @param base_url Character.
#' @param api_key Character.
#' @param timeout Numeric.
#' @param model Character.
#' @param messages List.
#' @param completion Character.
#' @param extra_body List.
#' @param apply_constraint_fn Function. Takes `(body, labels)` and adds the
#'   backend-specific constraint field.
#' @return A list with `completion` and `logprobs`.
#' @keywords internal
omni_forced_score <- function(base_url, api_key, timeout, model, messages,
                               completion, extra_body = list(),
                               apply_constraint_fn) {
  body <- build_omni_body(
    model, messages, temperature = 0, logprobs = TRUE,
    top_logprobs = 1, max_tokens = 256, extra_body = extra_body
  )
  body <- apply_constraint_fn(body, completion)

  response <- send_omni_chat(base_url, api_key, timeout, body)
  lps <- filter_special_tokens(response$logprobs %||% list())

  if (length(lps) == 0) {
    stop(sprintf("score(%s): forced generation returned no value tokens",
                 deparse(completion)), call. = FALSE)
  }

  list(completion = completion, logprobs = lps, raw = response$raw)
}

#' Tokenize text via empirical forced constrained generation
#'
#' Forces `text` as the only valid label in a constrained `chat()` call and
#' reads back the emitted value tokens. This is necessary because standalone
#' BPE tokenization (via `/tokenize`) produces different token boundaries
#' than the model emits under constraint guidance, which would break
#' trie-based divergence scoring. Results are memoized per label.
#'
#' @param base_url Character.
#' @param api_key Character.
#' @param timeout Numeric.
#' @param model Character.
#' @param text Character. The text to tokenize.
#' @param context Character or `NULL`. Ignored (accepted for interface compat).
#' @param extra_body List.
#' @param apply_constraint_fn Function. Takes `(body, labels)` and adds the
#'   backend-specific constraint field.
#' @param token_cache Environment. Memoization cache.
#' @return Character vector of token strings.
#' @keywords internal
omni_forced_tokenize <- function(base_url, api_key, timeout, model, text,
                                  context = NULL, extra_body = list(),
                                  apply_constraint_fn, token_cache = NULL) {
  # Check cache
  if (!is.null(token_cache) && !is.null(token_cache[[text]])) {
    return(token_cache[[text]])
  }

  body <- build_omni_body(
    model, list(list(role = "user", content = text)),
    temperature = 0, logprobs = TRUE, top_logprobs = 1,
    max_tokens = 256, extra_body = extra_body
  )
  body <- apply_constraint_fn(body, text)

  response <- send_omni_chat(base_url, api_key, timeout, body)
  lps <- filter_special_tokens(response$logprobs %||% list())
  tokens <- purrr::map_chr(lps, "token")
  if (length(tokens) == 0) tokens <- text

  # Memoize
  if (!is.null(token_cache)) {
    token_cache[[text]] <- tokens
  }

  tokens
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
#' reconstruction and completion scoring.
#'
#' Modern Ollama removed the `/api/tokenize` endpoint and does not support
#' fill-in-the-middle ("insert") on instruct models. This backend therefore
#' obtains both label tokenization and completion scores through empirical
#' *forced constrained generation* (forcing a label as the only valid choice
#' and reading back the model's genuine per-token logprobs). No
#' `/api/tokenize` or `suffix`/insert calls are used. Tokenization results
#' are memoized per label.
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
  # Empirical tokenization is deterministic per label (the JSON wrapper
  # prefix is constant), so memoize per label to amortize the setup cost.
  token_cache <- new.env(parent = emptyenv())

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
    ollama_score(host, model, messages, completion, extra_body, token_cache)
  }

  tokenize_fn <- function(text, context = NULL) {
    ollama_tokenize(host, model, text, context, token_cache)
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
#' serving engine with an OpenAI-compatible API. It supports
#' `structured_outputs.choice` (vLLM v0.12.0+) for bare-label constrained
#' generation, generating bare label text with no JSON wrapper.
#'
#' `score()` uses echo/prefill (`/v1/completions` with `echo=TRUE`) to
#' recover genuine per-label logprobs. `tokenize()` uses forced constrained
#' generation so token boundaries match the actual constrained-generation
#' output. Results are memoized per label.
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
  token_cache <- new.env(parent = emptyenv())

  # Apply structured_outputs.choice constraint (vLLM v0.12.0+)
  apply_constraint <- function(body, labels) {
    body$structured_outputs <- list(choice = labels)
    body
  }

  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- build_omni_body(model, messages, temperature, logprobs, top_logprobs,
                             max_tokens, extra_body)
    if (!is.null(constrain_labels)) body <- apply_constraint(body, constrain_labels)
    send_omni_chat(base_url, api_key, timeout, body)
  }

  score_fn <- function(messages, completion) {
    omni_score(base_url, api_key, timeout, model, messages, completion, extra_body)
  }

  tokenize_fn <- function(text, context = NULL) {
    omni_forced_tokenize(base_url, api_key, timeout, model, text, context,
                          extra_body, apply_constraint, token_cache)
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
#' bare-label generation, producing clean label text with no JSON wrapper.
#'
#' `score()` uses echo/prefill (`/v1/completions` with `echo=TRUE`) to
#' recover genuine per-label logprobs. `tokenize()` uses forced constrained
#' generation via regex so token boundaries match the actual
#' constrained-generation output. Results are memoized per label.
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
  token_cache <- new.env(parent = emptyenv())

  # Apply regex constraint for bare-label generation
  apply_constraint <- function(body, labels) {
    escaped <- purrr::map_chr(labels, ~ gsub("([\\[\\]{}.|*+?()^$])", "\\\\\\1", .x))
    body$regex <- paste0("(", paste(escaped, collapse = "|"), ")")
    body
  }

  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- build_omni_body(model, messages, temperature, logprobs, top_logprobs,
                             max_tokens, extra_body)
    if (!is.null(constrain_labels)) body <- apply_constraint(body, constrain_labels)
    send_omni_chat(base_url, api_key, timeout, body)
  }

  score_fn <- function(messages, completion) {
    omni_score(base_url, api_key, timeout, model, messages, completion, extra_body)
  }

  tokenize_fn <- function(text, context = NULL) {
    omni_forced_tokenize(base_url, api_key, timeout, model, text, context,
                          extra_body, apply_constraint, token_cache)
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
#' Both `score()` and `tokenize()` use forced constrained generation via
#' GBNF grammar because llama.cpp does not support `echo=TRUE` on the
#' completions endpoint (it only returns generated-token logprobs, not
#' prompt tokens). Results are memoized per label.
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
  token_cache <- new.env(parent = emptyenv())

  # Apply GBNF grammar constraint: root ::= "label1" | "label2" | "label3"
  apply_constraint <- function(body, labels) {
    quoted <- purrr::map_chr(labels, ~ paste0('"', .x, '"'))
    body$grammar <- paste0("root ::= ", paste(quoted, collapse = " | "))
    body
  }

  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- build_omni_body(model, messages, temperature, logprobs, top_logprobs,
                             max_tokens, extra_body)
    if (!is.null(constrain_labels)) body <- apply_constraint(body, constrain_labels)
    send_omni_chat(base_url, api_key, timeout, body)
  }

  score_fn <- function(messages, completion) {
    omni_forced_score(base_url, api_key, timeout, model, messages, completion,
                       extra_body, apply_constraint)
  }

  tokenize_fn <- function(text, context = NULL) {
    omni_forced_tokenize(base_url, api_key, timeout, model, text, context,
                          extra_body, apply_constraint, token_cache)
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
