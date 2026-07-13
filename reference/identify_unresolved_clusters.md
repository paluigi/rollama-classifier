# Identify unresolved clusters

Groups labels that are not fully resolved (scored_length \< full length)
and share a common prefix at the already-scored positions.

## Usage

``` r
identify_unresolved_clusters(token_sequences, scored_lengths)
```

## Arguments

- token_sequences:

  Named list of `{label: [tokens]}`.

- scored_lengths:

  Named integer vector.

## Value

A list of cluster lists, each with `labels` (character vector) and
`resolved_length` (integer).
