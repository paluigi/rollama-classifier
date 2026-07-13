# Classification Result

Result of a classification operation. Returned by
[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md),
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md),
and their batch variants.

## Usage

``` r
classification_result(
  prediction,
  confidence,
  probabilities,
  method = "multi_call",
  approximate = FALSE,
  coverage = numeric(0),
  n_calls = 1L,
  raw_response = list()
)
```

## Arguments

- prediction:

  Character. The predicted class label.

- confidence:

  Numeric between 0 and 1. Confidence score for the prediction.

- probabilities:

  Named numeric vector. Probability distribution over all choices (sums
  to 1).

- method:

  Character. Scoring method used: `"adaptive_generate"` or
  `"multi_call"`.

- approximate:

  Logical. `TRUE` if any label has partial coverage (unresolved tokens).
  Only relevant for `adaptive_generate`; always `FALSE` for
  `multi_call`.

- coverage:

  Named numeric vector. Per-label fraction of tokens scored (0.0 to
  1.0). `1.0` = fully resolved.

- n_calls:

  Integer. Number of API calls made.

- raw_response:

  List. Raw response data for debugging.

## Value

A list of class `classification_result` with components:

- prediction:

  Character. The predicted label.

- confidence:

  Numeric. Confidence score (0-1).

- probabilities:

  Named numeric vector. Probability distribution.

- method:

  Character. Scoring method used.

- approximate:

  Logical. Whether scores are approximate.

- coverage:

  Named numeric vector. Per-label token coverage.

- n_calls:

  Integer. Number of API calls.

- raw_response:

  List. Raw API response for debugging.

## Examples

``` r
res <- classification_result(
  prediction = "positive",
  confidence = 0.85,
  probabilities = c(positive = 0.85, negative = 0.10, neutral = 0.05)
)
print(res$prediction)
#> [1] "positive"
```
