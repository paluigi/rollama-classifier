# Find divergence point between two token sequences

Returns the 1-based index of the first position where the two sequences
differ. If they are identical up to the minimum length, returns
`min_len + 1` (meaning "no divergence within the overlapping range").

## Usage

``` r
divergence_point(label_tokens, winning_tokens)
```

## Arguments

- label_tokens:

  Character vector.

- winning_tokens:

  Character vector.

## Value

Integer. First 1-based index where they differ, or `min_len + 1`.
