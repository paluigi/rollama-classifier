#' rollama: Classify Text with LLMs on Ollama and Other Backends
#'
#' @description
#' A wrapper around the Ollama REST API and other inference engines
#' (vLLM, SGLang, llama.cpp) for text classification with constrained output
#' and confidence scoring.
#'
#' @section Features:
#' \itemize{
#'   \item Constrained output via JSON schema with enum constraints
#'   \item Confidence scoring via multi-call evaluation with softmax
#'   \item Batch processing for multiple texts
#'   \item Support for simple labels or labels with descriptions
#'   \item Custom system prompt overrides
#'   \item Multiple inference backends: Ollama, vLLM, SGLang, llama.cpp
#' }
#'
#' @section Ollama Backend (original):
#' ```r
#' classifier <- ollama_classifier("llama3.2")
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
#' @section Generic Backend (vLLM, SGLang, llama.cpp):
#' ```r
#' backend <- vllm_backend("meta-llama/Llama-3.2-3B-Instruct")
#' classifier <- llm_classifier(backend)
#'
#' result <- classify(
#'   classifier,
#'   text = "I love this product!",
#'   choices = c("positive", "negative", "neutral")
#' )
#' ```
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
