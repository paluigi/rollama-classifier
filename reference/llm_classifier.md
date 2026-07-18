# Unified LLM Classifier

Create a backend-agnostic classifier with two confidence scoring
methods:

- [`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md):
  Hierarchical constrained generation. A single constrained call
  produces a probability distribution over all labels using
  divergence-aware logprobs from the winning path. When `max_calls > 1`,
  supplementary calls resolve clusters of labels that share a token
  prefix but diverge from the winner — but only to **reproportion**
  probability mass *within* each cluster, never changing between-group
  totals. This guarantees accuracy never degrades as the call budget
  grows.

- [`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md):
  Multi-call completion scoring with geometric-mean normalization.
  Always exact. Makes N calls for N labels.

## Usage

``` r
llm_classifier(backend)
```

## Arguments

- backend:

  A backend object created by
  [`ollama_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/ollama_backend.md),
  [`vllm_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/vllm_backend.md),
  [`sglang_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/sglang_backend.md),
  or
  [`llamacpp_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llamacpp_backend.md).

## Value

A classifier object (list of closures) usable with the S3 generics
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md),
[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md),
[`batch_generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/batch_generate.md),
[`batch_classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/batch_classify.md).

## Examples

``` r
if (FALSE) { # \dontrun{
backend <- ollama_backend("llama3.2")
classifier <- llm_classifier(backend)

result <- classify(
  classifier,
  text = "I love this product!",
  choices = c("positive", "negative", "neutral")
)
print(result$prediction)
print(result$confidence)
} # }
```
