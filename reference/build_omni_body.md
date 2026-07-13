# Build base OpenAI-compatible request body

Build base OpenAI-compatible request body

## Usage

``` r
build_omni_body(
  model,
  messages,
  temperature = 0,
  logprobs = FALSE,
  top_logprobs = 5,
  max_tokens = 256,
  extra_body = list()
)
```

## Arguments

- model:

  Character. Model identifier.

- messages:

  List of message lists.

- temperature:

  Numeric. Sampling temperature.

- logprobs:

  Logical. Whether to return log probabilities.

- top_logprobs:

  Integer. Number of top log probs per token.

- max_tokens:

  Integer. Max tokens to generate.

- extra_body:

  List. Extra parameters to merge.

## Value

A list representing the request body.
