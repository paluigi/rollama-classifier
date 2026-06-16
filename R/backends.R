#' vLLM Backend
#'
#' @description
#' Create a backend for the vLLM inference server. vLLM provides a
#' high-throughput serving engine with an OpenAI-compatible API.
#'
#' @param model Character. Model identifier.
#' @param base_url Character. Base URL of the vLLM server.
#'   Defaults to `"http://localhost:8000/v1"`.
#' @param api_key Character. API key. Defaults to `"not-needed"`.
#' @param timeout Numeric. Request timeout in seconds. Default 120.
#' @param max_tokens Integer. Max tokens to generate. Default 256.
#' @param extra_body List. Extra parameters merged into every request.
#'
#' @return A backend environment with methods `chat()` and `achat()`.
#' @export
#' @examples
#' \dontrun{
#' backend <- vllm_backend("meta-llama/Llama-3.2-3B-Instruct")
#' }
vllm_backend <- function(model, base_url = "http://localhost:8000/v1",
                          api_key = "not-needed", timeout = 120,
                          max_tokens = 256, extra_body = list()) {
  .build_body <- build_body
  .send <- send_chat_request

  chat_fn <- function(messages, temperature = 0, guided_json = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- .build_body(
      model = model,
      messages = purrr::map(messages, ~ list(role = .x$role, content = .x$content)),
      temperature = temperature,
      guided_json = guided_json,
      logprobs = logprobs,
      top_logprobs = top_logprobs,
      max_tokens = max_tokens,
      extra_body = extra_body
    )
    .send(base_url, api_key, timeout, body)
  }

  achat_fn <- chat_fn  # R has limited async; uses sync for now

  structure(
    list(
      chat = chat_fn,
      achat = achat_fn,
      model = model,
      base_url = base_url
    ),
    class = c("vllm_backend", "llm_backend")
  )
}

#' SGLang Backend
#'
#' @description
#' Create a backend for the SGLang inference server. SGLang is a fast
#' serving system for large language models.
#'
#' @param model Character. Model identifier.
#' @param base_url Character. Base URL of the SGLang server.
#'   Defaults to `"http://localhost:30000/v1"`.
#' @param api_key Character. API key. Defaults to `"not-needed"`.
#' @param timeout Numeric. Request timeout in seconds. Default 120.
#' @param max_tokens Integer. Max tokens to generate. Default 256.
#' @param extra_body List. Extra parameters merged into every request.
#'
#' @return A backend environment with methods `chat()` and `achat()`.
#' @export
#' @examples
#' \dontrun{
#' backend <- sglang_backend("meta-llama/Llama-3.2-3B-Instruct")
#' }
sglang_backend <- function(model, base_url = "http://localhost:30000/v1",
                            api_key = "not-needed", timeout = 120,
                            max_tokens = 256, extra_body = list()) {
  .build_body <- build_body
  .send <- send_chat_request

  chat_fn <- function(messages, temperature = 0, guided_json = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- .build_body(
      model = model,
      messages = purrr::map(messages, ~ list(role = .x$role, content = .x$content)),
      temperature = temperature,
      guided_json = guided_json,
      logprobs = logprobs,
      top_logprobs = top_logprobs,
      max_tokens = max_tokens,
      extra_body = extra_body
    )
    .send(base_url, api_key, timeout, body)
  }

  achat_fn <- chat_fn

  structure(
    list(
      chat = chat_fn,
      achat = achat_fn,
      model = model,
      base_url = base_url
    ),
    class = c("sglang_backend", "llm_backend")
  )
}

#' llama.cpp Backend
#'
#' @description
#' Create a backend for the llama.cpp server (`llama-server`). Ideal for CPU
#' or mixed CPU/GPU environments.
#'
#' @note JSON schema constraints and logprobs require llama.cpp to be
#'   compiled with `LLAMA_JSON_SCHEMA` and `LLAMA_SUPPORT_LOGPROBS` flags.
#'
#' @param model Character. Model identifier (filename or alias).
#' @param base_url Character. Base URL of the llama.cpp server.
#'   Defaults to `"http://localhost:8080/v1"`.
#' @param api_key Character. API key. Defaults to `"not-needed"`.
#' @param timeout Numeric. Request timeout in seconds. Default 120.
#' @param max_tokens Integer. Max tokens to generate. Default 256.
#' @param extra_body List. Extra parameters merged into every request.
#'
#' @return A backend environment with methods `chat()` and `achat()`.
#' @export
#' @examples
#' \dontrun{
#' backend <- llamacpp_backend("model")
#' }
llamacpp_backend <- function(model, base_url = "http://localhost:8080/v1",
                               api_key = "not-needed", timeout = 120,
                               max_tokens = 256, extra_body = list()) {
  .build_body <- build_body
  .send <- send_chat_request

  chat_fn <- function(messages, temperature = 0, guided_json = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    body <- .build_body(
      model = model,
      messages = purrr::map(messages, ~ list(role = .x$role, content = .x$content)),
      temperature = temperature,
      guided_json = guided_json,
      logprobs = logprobs,
      top_logprobs = top_logprobs,
      max_tokens = max_tokens,
      extra_body = extra_body
    )
    .send(base_url, api_key, timeout, body)
  }

  achat_fn <- chat_fn

  structure(
    list(
      chat = chat_fn,
      achat = achat_fn,
      model = model,
      base_url = base_url
    ),
    class = c("llamacpp_backend", "llm_backend")
  )
}
