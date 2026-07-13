# Score labels from winning path (divergence-aware)

For each label, computes the geometric-mean logprob over tokens up to
the divergence point from the winning path. Tokens at those positions
are exact because the conditioning prefix matches for both the label and
the winner up to that point.

## Usage

``` r
score_labels_from_winning_path(token_sequences, winning_label, step_logprobs)
```

## Arguments

- token_sequences:

  Named list of `{label: [tokens]}`.

- winning_label:

  Character. The label that the model actually generated.

- step_logprobs:

  List of named numeric vectors. `step_logprobs[[i]]` is a named numeric
  vector `{token: logprob}` for position i.

## Value

Named numeric vector of geometric-mean logprobs.
