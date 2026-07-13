# llama.cpp Backend

Backend for the llama.cpp server (`llama-server`). Uses GBNF grammar for
bare-label generation, producing clean label text with no JSON wrapper.

Both `score()` and `tokenize()` use forced constrained generation via
GBNF grammar because llama.cpp does not support `echo=TRUE` on the
completions endpoint (it only returns generated-token logprobs, not
prompt tokens). Results are memoized per label.

## Usage

``` r
llamacpp_backend(
  model,
  base_url = "http://localhost:8080/v1",
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
backend <- llamacpp_backend("model")
} # }
```
