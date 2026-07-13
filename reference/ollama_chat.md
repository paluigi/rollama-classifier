# Send a chat completion request to Ollama

Uses the native `/api/chat` endpoint. When `constrain_labels` is
provided, builds a JSON enum schema and passes it via the `format`
parameter.

## Usage

``` r
ollama_chat(
  base_url,
  model,
  messages,
  constrain_labels = NULL,
  logprobs = FALSE,
  top_logprobs = NULL,
  options = NULL
)
```

## Arguments

- base_url:

  Character. Base URL of the Ollama server.

- model:

  Character. Model name.

- messages:

  List of message lists, each with `role` and `content`.

- constrain_labels:

  Character vector or `NULL`. Labels to constrain output to.

- logprobs:

  Logical. Whether to return log probabilities.

- top_logprobs:

  Integer or `NULL`. Number of top alternatives per token.

- options:

  List. Additional model options.

## Value

A list with `content`, `label`, `logprobs`, and `raw`.
