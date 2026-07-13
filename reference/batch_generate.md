# Batch constrained generation

Batch constrained generation

## Usage

``` r
batch_generate(classifier, texts, choices, system_prompt = NULL, ...)
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

Character vector of predicted labels.
