# Classify text with calibrated confidence scores

Uses multi-call evaluation to compute calibrated probabilities for each
choice. Makes N API calls for N choices, computes log P(choice\|context)
for each, and applies softmax for calibrated probability scores.

## Usage

``` r
classify(classifier, text, choices, system_prompt = NULL, ...)
```

## Arguments

- classifier:

  A classifier object created by
  [`llm_classifier()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llm_classifier.md).

- text:

  Character. The text to classify.

- choices:

  Either a character vector of labels or a named list.

- system_prompt:

  Character or `NULL`. Optional custom system prompt.

- ...:

  Additional arguments.

## Value

A
[`classification_result()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classification_result.md)
list with prediction, confidence, probabilities, and raw_response.

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
