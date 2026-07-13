# Batch classification

Batch classification

## Usage

``` r
batch_classify(classifier, texts, choices, system_prompt = NULL, ...)
```

## Arguments

- classifier:

  A classifier object.

- texts:

  Character vector. Texts to classify.

- choices:

  Either a character vector of labels or a named list.

- system_prompt:

  Character or `NULL`. Optional custom system prompt.

- ...:

  Additional arguments.

## Value

A list of
[`classification_result()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classification_result.md)
objects.
