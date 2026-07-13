# Extract label-value tokens from a JSON-enum constrained response

Extracts the label-value tokens (with their logprobs) from a
`{"label": "<label>"}` constrained response.

## Usage

``` r
ollama_label_token_logprobs(logprobs, label)
```

## Arguments

- logprobs:

  List of logprob entries, each with `token`, `logprob`, and
  `top_logprobs`.

- label:

  Character. The label text to locate.

## Value

A filtered list of logprob entries (only the label-value tokens).

## Details

Robust to model-specific whitespace in the emitted JSON. The returned
tokens keep their *exact* emitted strings so they match the tokens the
model produces during multi-label constrained generation in
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md).

Primary strategy: reconstruct the full emitted string, locate the value
span after the JSON `:` separator, and map that character span back to
token indices. Falls back to JSON-skeleton filtering if the span mapping
yields nothing.
