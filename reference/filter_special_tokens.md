# Filter out special / end-of-sequence tokens from a logprobs list

For bare-label backends (vLLM, SGLang, llama.cpp), the constraint
guarantees only label text is generated, so we just need to remove
special/EOS tokens and empty strings.

## Usage

``` r
filter_special_tokens(logprobs)
```

## Arguments

- logprobs:

  List of logprob entries with `token`, `logprob`, `top_logprobs`.

## Value

Filtered list of logprob entries.
