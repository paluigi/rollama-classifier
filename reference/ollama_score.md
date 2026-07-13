# Score a completion by forcing it as the single valid label

Modern Ollama (and instruct models in general) do not support the
fill-in-the-middle ("insert") mode that `/api/generate` with `suffix=`
requires. Instead, this forces `completion` as the only valid label via
a JSON-enum constrained `chat()` call and reads back the model's genuine
per-token logprobs (teacher forcing). No free generation occurs beyond
the forced label.

## Usage

``` r
ollama_score(
  base_url,
  model,
  messages,
  completion,
  extra_body = list(),
  token_cache = NULL
)
```

## Arguments

- base_url:

  Character. Base URL of the Ollama server.

- model:

  Character. Model name.

- messages:

  List of message lists.

- completion:

  Character. The completion text to score.

- extra_body:

  List. Extra parameters for options.

- token_cache:

  Environment. Memoization cache for tokenize (shared).

## Value

A list with `completion` and `logprobs`.
