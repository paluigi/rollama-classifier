# Extract choice labels from either format

Extract choice labels from either format

## Usage

``` r
get_choice_labels(choices)
```

## Arguments

- choices:

  Either a character vector of labels or a named list.

## Value

Character vector of labels.

## Examples

``` r
get_choice_labels(c("a", "b", "c"))
#> [1] "a" "b" "c"
get_choice_labels(list(positive = "Happy", negative = "Sad"))
#> [1] "positive" "negative"
```
