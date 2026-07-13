# Score a completion via forced constrained generation (llama.cpp)

Forces `completion` as the only valid choice via the backend's
constraint mechanism and reads back the model's genuine per-token
logprobs (teacher forcing, pre-mask). Used by backends that do not
support `echo=TRUE` on the completions endpoint (llama.cpp).

## Usage

``` r
omni_forced_score(
  base_url,
  api_key,
  timeout,
  model,
  messages,
  completion,
  extra_body = list(),
  apply_constraint_fn
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

- messages:

  List.

- completion:

  Character.

- extra_body:

  List.

- apply_constraint_fn:

  Function. Takes `(body, labels)` and adds the backend-specific
  constraint field.

## Value

A list with `completion` and `logprobs`.
