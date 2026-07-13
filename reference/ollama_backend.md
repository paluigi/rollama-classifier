# Ollama Backend

Backend for the Ollama runtime (\>=v0.12) via the native Ollama REST
API.

Ollama uses JSON Schema enum for label constraints. The model generates
`{"label": "<chosen>"}`. Structural JSON tokens are filtered during trie
reconstruction and completion scoring.

Modern Ollama removed the `/api/tokenize` endpoint and does not support
fill-in-the-middle ("insert") on instruct models. This backend therefore
obtains both label tokenization and completion scores through empirical
*forced constrained generation* (forcing a label as the only valid
choice and reading back the model's genuine per-token logprobs). No
`/api/tokenize` or `suffix`/insert calls are used. Tokenization results
are memoized per label.

## Usage

``` r
ollama_backend(
  model,
  host = "http://localhost:11434",
  timeout = 120,
  max_tokens = 256,
  extra_body = list()
)
```

## Arguments

- model:

  Character. Model name (e.g., `"llama3.2"`).

- host:

  Character. Ollama server URL. Defaults to `"http://localhost:11434"`.

- timeout:

  Numeric. Request timeout in seconds.

- max_tokens:

  Integer. Max tokens to generate.

- extra_body:

  List. Extra parameters for options.

## Value

A backend list with `chat()`, `score()`, `tokenize()`, and capability
flags.

## Examples

``` r
if (FALSE) { # \dontrun{
backend <- ollama_backend("llama3.2")
classifier <- llm_classifier(backend)
} # }
```
