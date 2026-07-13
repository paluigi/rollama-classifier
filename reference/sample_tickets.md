# Sample Data for Testing rollama

A dataset of 20 customer support ticket texts across four categories:
billing, technical_support, account, and general.

## Usage

``` r
data(sample_tickets)

sample_tickets
```

## Format

A data frame with 20 rows and 4 columns:

- text:

  Character. Short text to classify.

- expected_label:

  Character. Expected correct label.

- label:

  Character. Simple category label.

- label_description:

  Character. Human-readable description of the category.

## Source

Internal dataset
