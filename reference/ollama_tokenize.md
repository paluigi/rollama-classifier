# Tokenize text via empirical forced generation

Modern Ollama removed the `/api/tokenize` endpoint (and the SDK no
longer exposes a `tokenize` method). To get the *exact* token strings
the model emits for `text` inside the JSON wrapper, this forces `text`
as the only valid label in a constrained `chat()` call and reads back
the emitted value tokens. Results are memoized per label.

## Usage

``` r
ollama_tokenize(base_url, model, text, context = NULL, token_cache = NULL)
```

## Arguments

- base_url:

  Character. Base URL of the Ollama server.

- model:

  Character. Model name.

- text:

  Character. The text to tokenize.

- context:

  Character or `NULL`. Ignored (accepted for interface compat).

- token_cache:

  Environment. Memoization cache.

## Value

Character vector of token strings.

## Details

The `context` argument is accepted for interface compatibility but
ignored: Ollama always wraps the label in the constant JSON prefix
(double-quote-brace-label-colon-space-double-quote) regardless of
surrounding prompt tokens.
