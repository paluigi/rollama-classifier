#' rollama: Classify Text with LLMs on Ollama and Other Backends
#'
#' @description
#' A wrapper around the Ollama REST API and other inference engines
#' (vLLM, SGLang, llama.cpp) for text classification with constrained output
#' and confidence scoring. All backends use empirical forced constrained
#' generation for tokenization and echo/prefill or forced generation for
#' completion scoring. Provides two scoring methods:
#'
#' - `generate()`: Adaptive constrained generation with divergence-aware
#'   confidence scoring, budget-controlled via `max_calls`.
#' - `classify()`: Multi-call completion scoring with geometric-mean
#'   normalization. Gold-standard accuracy.
#'
#' @section Features:
#' \itemize{
#'   \item Adaptive constrained generation with trie-based confidence scoring
#'   \item Multi-call completion scoring with geometric-mean normalization
#'   \item Eliminates confidence concentration bias from raw logprob sums
#'   \item Support for multiple inference backends: Ollama, vLLM, SGLang, llama.cpp
#'   \item Batch processing for multiple texts
#'   \item Support for simple labels or labels with descriptions
#' }
#'
#' @section Quick Start:
#' ```r
#' backend <- ollama_backend("llama3.2")
#' classifier <- llm_classifier(backend)
#'
#' result <- classify(
#'   classifier,
#'   text = "I love this product!",
#'   choices = c("positive", "negative", "neutral")
#' )
#' print(result$prediction)
#' print(result$confidence)
#' ```
#'
#' @section Choosing a Scoring Method:
#'
#' | Method | API Calls | Exactness | When to Use |
#' |--------|-----------|-----------|------------|
#' | `generate(max_calls = 1)` | 1 | Approximate | Speed-critical |
#' | `generate(max_calls = NULL)` | 1-N | Exact | Adaptive resolution |
#' | `classify()` | N | Always exact | Research, calibration |
#'
#' @docType package
#' @name rollama
#' @aliases rollama rollama-package
#'
#' @author Luigi Palumbo \email{paluigi@users.noreply.github.com},
#'   Mengting Yu, Carolina Camassa
#'
#' @references \url{https://github.com/paluigi/rollama-classifier}
#'
#' @keywords internal
#' @importFrom httr2 request req_method req_headers req_body_json req_timeout req_perform resp_body_json
#' @importFrom rlang %||%
#' @importFrom tibble tibble
"_PACKAGE"
