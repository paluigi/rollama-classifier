# Build the system and user prompts for classification

Build the system and user prompts for classification

## Usage

``` r
build_classification_prompt(text, choices, system_prompt = NULL)
```

## Arguments

- text:

  Character. The text to classify.

- choices:

  Either a character vector of labels or a named list.

- system_prompt:

  Character or `NULL`. Optional custom system prompt.

## Value

A list with components `system` and `user`.

## Examples

``` r
build_classification_prompt(
  "I love this!",
  c("positive", "negative", "neutral")
)
#> $system
#> [1] "You are a precise text classifier. Your task is to classify the given text into exactly one of the provided categories. Respond with only the category label, nothing else."
#> 
#> $user
#> [1] "Classify the following text into one of these categories:\n\n- positive\n- negative\n- neutral\n\nText to classify:\nI love this!\n\nRespond with only the category label."
#> 
```
