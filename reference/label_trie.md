# Create an empty label trie

The trie is a nested list structure used by
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)
to:

1.  Determine the minimum `top_logprobs` K (max branching factor).

2.  Find divergence points between the winning path and each label.

3.  Identify unresolved clusters for recursive resolution.

## Usage

``` r
label_trie()
```

## Value

A list representing an empty trie.
