# Count tokens via OpenAI-compatible tokenize endpoint

Uses the correct `"prompt"` field name for the `/tokenize` endpoint.
Raises on HTTP errors — no silent masking.

## Usage

``` r
omni_tokenize_count(base_url, api_key, timeout, model, text)
```

## Arguments

- base_url:

  Character. Base URL (with `/v1`).

- api_key:

  Character. API key.

- timeout:

  Numeric. Timeout in seconds.

- model:

  Character. Model name.

- text:

  Character. Text to tokenize.

## Value

Integer. Number of tokens.
