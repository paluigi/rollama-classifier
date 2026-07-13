# vLLM Backend

Backend for the vLLM inference server. vLLM provides a high-throughput
serving engine with an OpenAI-compatible API. It supports
`structured_outputs.choice` (vLLM v0.12.0+) for bare-label constrained
generation, generating bare label text with no JSON wrapper.

`score()` uses echo/prefill (`/v1/completions` with `echo=TRUE`) to
recover genuine per-label logprobs. `tokenize()` uses forced constrained
generation so token boundaries match the actual constrained-generation
output. Results are memoized per label.

## Usage

``` r
vllm_backend(
  model,
  base_url = "http://localhost:8000/v1",
  api_key = "not-needed",
  timeout = 120,
  max_tokens = 256,
  extra_body = list()
)
```

## Arguments

- model:

  Character. Model identifier.

- base_url:

  Character. Base URL of the vLLM server.

- api_key:

  Character. API key.

- timeout:

  Numeric. Request timeout in seconds.

- max_tokens:

  Integer. Max tokens to generate.

- extra_body:

  List. Extra parameters merged into every request.

## Value

A backend list.

## Examples

``` r
if (FALSE) { # \dontrun{
backend <- vllm_backend("meta-llama/Llama-3.2-3B-Instruct")
} # }
```
