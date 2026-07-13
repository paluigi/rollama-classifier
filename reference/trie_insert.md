# Insert a label into the trie

Uses a recursive approach to rebuild the nested list, since R lists are
copy-on-modify and in-place mutation of nested nodes does not work.

## Usage

``` r
trie_insert(trie, label, tokens)
```

## Arguments

- trie:

  A trie from
  [`label_trie()`](https://paluigi-moltis.github.io/rollama-classifier/reference/label_trie.md).

- label:

  Character. The label name.

- tokens:

  Character vector of token strings.

## Value

A modified copy of the trie.
