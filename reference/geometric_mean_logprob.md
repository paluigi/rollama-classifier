# Geometric-mean (length-normalized) log probability

Computes the per-token average of log probabilities, equivalent to the
log of the geometric mean of token probabilities. Eliminates the length
bias that occurs when summing raw logprobs over labels with different
token counts.

## Usage

``` r
geometric_mean_logprob(logprobs)
```

## Arguments

- logprobs:

  Numeric vector of per-token log probabilities.

## Value

Numeric. Average per-token log probability.
