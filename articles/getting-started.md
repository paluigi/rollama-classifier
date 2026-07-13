# Getting Started with rollama

The `rollama` package provides text classification with constrained
output and calibrated confidence scoring using four inference backends:
**Ollama**, **vLLM**, **SGLang**, and **llama.cpp**.

Every backend is constructed with a backend function and wrapped in a
single
[`llm_classifier()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llm_classifier.md).
The classifier then offers two scoring methods —
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)
and
[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md)
— both returning a `classification_result` with a prediction,
confidence, and a full probability distribution.

## Installation

``` r
# Install from GitHub
# install.packages("pak")
pak::pak("paluigi/rollama-classifier")
```

### Prerequisites

**Ollama backend**: Install [Ollama](https://ollama.com/download)
(\>=v0.12) and pull a model:

``` bash
ollama pull llama3.2
```

Recommended models: `llama3.2`, `llama3.1`, `mistral`, `qwen2.5`.

## Quick Start

### Ollama Backend

``` r
library(rollama)

backend <- ollama_backend(model = "llama3.2")
classifier <- llm_classifier(backend)

result <- classify(
  classifier,
  text = "I love this product!",
  choices = c("positive", "negative", "neutral")
)

print(result$prediction)
#> "positive"
print(result$confidence)
#> 0.85
```

### vLLM Backend

``` r
backend <- vllm_backend("meta-llama/Llama-3.2-3B-Instruct")
classifier <- llm_classifier(backend)

result <- classify(
  classifier,
  text = "I love this product!",
  choices = c("positive", "negative", "neutral")
)
```

## `generate()` vs `classify()`

rollama offers two complementary scoring methods. Both return a
`classification_result`; they differ in how they spend API calls and how
their confidence is computed.

|                   | [`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md) | [`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md) |
|-------------------|-------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| **Strategy**      | Adaptive trie-masked generation                                                           | Multi-call completion scoring                                                             |
| **API calls**     | 1 to `max_calls` (budget-controlled)                                                      | N calls for N labels                                                                      |
| **Confidence**    | Divergence-aware; exact when fully resolved                                               | Always exact (calibrated)                                                                 |
| **Normalization** | Geometric mean of per-token logprobs                                                      | Geometric mean of per-token logprobs                                                      |
| **`method`**      | `"adaptive_generate"`                                                                     | `"multi_call"`                                                                            |
| **`approximate`** | `TRUE` if any label has partial coverage                                                  | Always `FALSE`                                                                            |

- **[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)**
  makes one or a few constrained calls and reconstructs per-label
  logprobs from the winning generation path using a prefix trie. It is
  fast and budget-controlled, but the result may be *approximate* when
  the budget runs out before every label is fully resolved.
- **[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md)**
  scores every label independently via the backend’s completion-scoring
  endpoint, then applies a softmax over geometric-mean-normalized
  scores. It always makes N calls for N labels and is always exact.

### `max_calls`

The `max_calls` argument controls
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)’s
API budget:

| `max_calls`   | Behavior                                   | `approximate`   |
|---------------|--------------------------------------------|-----------------|
| `1` (default) | Single constrained call; fast              | Possibly `TRUE` |
| `K` (integer) | Adaptive: resolves ambiguity up to K calls | Possibly `TRUE` |
| `NULL`        | Resolves all labels; exact                 | `FALSE`         |

``` r
# Fast, single-call prediction (may be approximate)
result <- generate(classifier, text = txt, choices = choices, max_calls = 1)
print(result$approximate) # TRUE if any label was only partially scored

# Adaptive: spend up to 3 calls to resolve ambiguities
result <- generate(classifier, text = txt, choices = choices, max_calls = 3)

# Exact: resolve every label fully
result <- generate(classifier, text = txt, choices = choices, max_calls = NULL)
```

### `coverage` and `approximate`

When
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)
cannot fully resolve a label within the call budget, that label’s token
logprobs are only partially known. Two fields report this:

- **`result$coverage`** — a named numeric vector giving the fraction of
  tokens scored per label (0.0 to 1.0). `1.0` means the label is fully
  resolved.
- **`result$approximate`** — `TRUE` if *any* label has coverage below
  1.0. For
  [`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md)
  this is always `FALSE`.

``` r
result <- generate(classifier, text = txt, choices = choices, max_calls = 1)

print(result$coverage)
#>   positive    negative     neutral
#>         1.0         0.5         1.0
print(result$approximate)
#> TRUE
print(result$n_calls)
#> 1
```

## Usage Patterns

### Basic Classification

Classify text into predefined choices:

``` r
backend <- ollama_backend(model = "llama3.2")
classifier <- llm_classifier(backend)

result <- classify(
  classifier,
  text = "The goalkeeper made an incredible save!",
  choices = c("sports", "politics", "technology", "entertainment")
)
```

### Classification with Label Descriptions

Providing descriptions helps the model understand each category better:

``` r
choices <- list(
  positive = "Text expresses happiness, satisfaction, or approval",
  negative = "Text expresses anger, disappointment, or disapproval",
  mixed = "Text contains both positive and negative sentiments",
  neutral = "Text is factual without strong emotional content"
)

result <- classify(
  classifier,
  text = "The food was amazing but the service was terrible.",
  choices = choices
)
```

### Custom System Prompt

Override the default system prompt for specialized tasks:

``` r
result <- classify(
  classifier,
  text = "The quarterly earnings exceeded analyst expectations.",
  choices = c("bullish", "bearish", "neutral"),
  system_prompt = "You are a financial sentiment analyzer.
                   Classify financial news based on market sentiment."
)
```

### Adaptive Generation

[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)
returns a `classification_result` just like
[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md),
reconstructed from constrained generation:

``` r
result <- generate(
  classifier,
  text = "The team won the championship!",
  choices = c("sports", "finance", "politics"),
  max_calls = 1
)

print(result$prediction)
print(result$confidence)
print(result$method)      # "adaptive_generate"
print(result$approximate) # TRUE if any label is partially scored
```

### Batch Classification

Classify multiple texts efficiently. The batch variants return a list of
`classification_result` objects:

``` r
texts <- c(
  "The goalkeeper made an incredible save!",
  "The central bank raised interest rates.",
  "The new smartphone features a revolutionary camera."
)

results <- batch_classify(
  classifier,
  texts = texts,
  choices = c("sports", "finance", "technology")
)

purrr::map2_chr(texts, results, ~ paste0(.x, " -> ", .y$prediction))
```

### Custom System Prompt with Batch

``` r
results <- batch_classify(
  classifier,
  texts = texts,
  choices = c("bullish", "bearish", "neutral"),
  system_prompt = "You are a financial sentiment analyzer."
)
```

## The `classification_result` Object

Both methods return the same structure:

``` r
result$prediction      # Character: predicted label
result$confidence      # Numeric (0-1): confidence score
result$probabilities   # Named numeric: probability distribution (sums to 1)
result$method          # "adaptive_generate" or "multi_call"
result$approximate     # Logical: TRUE if any label has partial coverage
result$coverage        # Named numeric: per-label token coverage (0.0-1.0)
result$n_calls         # Integer: number of API calls made
result$raw_response    # List: raw data for debugging
```

## Choosing a Method

| Use Case                               | Recommended Method                                                                                                                                                                                             |
|----------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Speed is critical, limited call budget | `generate(max_calls = 1)`                                                                                                                                                                                      |
| Balanced speed and accuracy            | `generate(max_calls = K)`                                                                                                                                                                                      |
| Exact confidence on a budget           | `generate(max_calls = NULL)`                                                                                                                                                                                   |
| Maximum calibration accuracy           | [`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md)                                                                                                                      |
| Batch processing                       | [`batch_classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/batch_classify.md) or [`batch_generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/batch_generate.md) |

## Sample Data

The package ships with a sample dataset of 20 customer support tickets:

``` r
data(sample_tickets, package = "rollama")
head(sample_tickets)
#>                                                             text
#> 1                          I was charged twice for my last order
#> 2 Can I get a refund for the subscription I cancelled last week?
#> 3       My invoice shows a different amount than what was quoted
#> 4                           Where can I find my payment history?
#> 5                          I need an update on my pending refund
#> 6             The app keeps crashing when I try to upload a file
#>      expected_label             label
#> 1           billing           billing
#> 2           billing           billing
#> 3           billing           billing
#> 4           billing           billing
#> 5           billing           billing
#> 6 technical_support technical_support
#>                                                              label_description
#> 1 Questions about charges, invoices, payments, refunds, and subscription costs
#> 2 Questions about charges, invoices, payments, refunds, and subscription costs
#> 3 Questions about charges, invoices, payments, refunds, and subscription costs
#> 4 Questions about charges, invoices, payments, refunds, and subscription costs
#> 5 Questions about charges, invoices, payments, refunds, and subscription costs
#> 6           Issues with software, bugs, errors, login problems, or performance
```

``` r
# Test classification accuracy
results <- batch_classify(
  classifier,
  texts = sample_tickets$text,
  choices = c("billing", "technical_support", "account", "general")
)

predictions <- purrr::map_chr(results, "prediction")
mean(predictions == sample_tickets$expected_label)
```
