# Get max branching factor of trie

Returns the maximum number of children at any node. This is the minimum
`top_logprobs` K needed to capture all sibling alternatives.

## Usage

``` r
trie_max_branching(trie)
```

## Arguments

- trie:

  A trie from
  [`label_trie()`](https://paluigi-moltis.github.io/rollama-classifier/reference/label_trie.md).

## Value

Integer. Max children count at any node.
