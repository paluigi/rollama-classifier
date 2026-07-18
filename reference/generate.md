# Generate a constrained classification

Generic for hierarchical constrained generation. Makes 1 to `max_calls`
constrained API calls. The first call constrains the model to all labels
and produces an internally consistent probability distribution.
Supplementary calls (when `max_calls > 1`) resolve label clusters by
**reproportioning** probability mass within a cluster — they never
change between-group totals, so accuracy cannot degrade as the call
budget grows.

## Usage

``` r
generate(classifier, text, choices, system_prompt = NULL, ..., max_calls = 1L)
```

## Arguments

- classifier:

  A classifier object created by
  [`llm_classifier()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llm_classifier.md).

- text:

  Character. The text to classify.

- choices:

  Either a character vector of labels or a named list mapping labels to
  descriptions.

- system_prompt:

  Character or `NULL`. Optional custom system prompt.

- ...:

  Additional arguments (for future extensibility).

- max_calls:

  Integer or `NULL`. Maximum number of API calls. `1` = single call, no
  cluster resolution (default). `K` = adaptive resolution up to K calls.
  `NULL` = resolve all clusters recursively.

## Value

A
[`classification_result()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classification_result.md)
list.

## Examples

``` r
if (FALSE) { # \dontrun{
backend <- ollama_backend("llama3.2")
classifier <- llm_classifier(backend)
result <- generate(
  classifier,
  text = "The team won the championship!",
  choices = c("sports", "finance", "politics")
)
} # }
```
