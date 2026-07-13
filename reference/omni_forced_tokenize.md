# Tokenize text via empirical forced constrained generation

Forces `text` as the only valid label in a constrained `chat()` call and
reads back the emitted value tokens. This is necessary because
standalone BPE tokenization (via `/tokenize`) produces different token
boundaries than the model emits under constraint guidance, which would
break trie-based divergence scoring. Results are memoized per label.

## Usage

``` r
omni_forced_tokenize(
  base_url,
  api_key,
  timeout,
  model,
  text,
  context = NULL,
  extra_body = list(),
  apply_constraint_fn,
  token_cache = NULL
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

- text:

  Character. The text to tokenize.

- context:

  Character or `NULL`. Ignored (accepted for interface compat).

- extra_body:

  List.

- apply_constraint_fn:

  Function. Takes `(body, labels)` and adds the backend-specific
  constraint field.

- token_cache:

  Environment. Memoization cache.

## Value

Character vector of token strings.
