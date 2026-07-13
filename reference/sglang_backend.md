# SGLang Backend

Backend for the SGLang inference server. Uses regex constraint for
bare-label generation, producing clean label text with no JSON wrapper.

`score()` uses echo/prefill (`/v1/completions` with `echo=TRUE`) to
recover genuine per-label logprobs. `tokenize()` uses forced constrained
generation via regex so token boundaries match the actual
constrained-generation output. Results are memoized per label.

## Usage

``` r
sglang_backend(
  model,
  base_url = "http://localhost:30000/v1",
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
backend <- sglang_backend("meta-llama/Llama-3.2-3B-Instruct")
} # }
```
