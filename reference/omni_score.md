# Score a completion via echo/prefill logprobs (vLLM, SGLang)

Uses `/v1/completions` with `echo=TRUE` to recover the model's genuine
per-token logprobs for the label as an unexpected continuation of the
prompt. The `/tokenize` endpoint pinpoints the exact label-token
boundary. The spurious `max_tokens=1` generated token is discarded by
slicing to `total_len`.

## Usage

``` r
omni_score(
  base_url,
  api_key,
  timeout,
  model,
  messages,
  completion,
  extra_body = list()
)
```

## Arguments

- base_url:

  Character.

- api_key:

  Character.

- timeout:

  Numeric.

- model:

  Character.

- messages:

  List.

- completion:

  Character.

- extra_body:

  List.

## Value

A list with `completion` and `logprobs`.
