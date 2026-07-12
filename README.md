# rollama

Text classification with LLMs using constrained output and calibrated
confidence scoring. Supports four inference backends through a single
unified API: **Ollama, vLLM, SGLang, and llama.cpp**.

rollama offers two complementary scoring methods:

- **`generate()`** — Adaptive constrained generation. Reconstructs
  per-label logprobs from one or a few constrained API calls using a
  prefix trie. Budget-controlled via `max_calls`.
- **`classify()`** — Multi-call completion scoring. Scores every label
  independently with geometric-mean normalization for exact, calibrated
  probabilities.

Both return a `classification_result` with a prediction, confidence,
a full probability distribution, and diagnostics.

## Features

- **Two scoring methods**: adaptive `generate()` and exact `classify()`
- **Calibrated confidence**: geometric-mean normalization eliminates the
  length/concentration bias of raw logprob summation
- **Constrained output**: every backend constrains generation to valid
  labels (JSON enum, `structured_outputs.choice`, regex, or GBNF grammar)
- **Budget control**: `max_calls` lets you trade accuracy for speed
- **Unified backends**: one `llm_classifier()` works with Ollama, vLLM,
  SGLang, and llama.cpp
- **Flexible choices**: simple labels or labels with descriptions
- **Custom prompts**: override the default system prompt
- **Batch processing**: classify many texts at once

## Installation

```r
# Install from GitHub
pak::pak("paluigi/rollama-classifier")

# Or with remotes
remotes::install_github("paluigi/rollama-classifier")
```

### Prerequisites

You need one inference server running locally or remotely:

- **Ollama** (>=v0.12): [Ollama](https://ollama.com/download) installed and
  running, with a model pulled (e.g., `ollama pull llama3.2`)
- **vLLM**: a running [vLLM](https://docs.vllm.ai/) server
- **SGLang**: a running [SGLang](https://sglang.ai/) server
- **llama.cpp**: a running [llama.cpp server](https://github.com/ggerganov/llama.cpp/tree/master/examples/server)

## Quick Start

### Ollama

```r
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
print(result$probabilities)
#> positive  negative    neutral
#>     0.85      0.10      0.05
```

### vLLM

```r
backend <- vllm_backend(
  model = "meta-llama/Llama-3.2-3B-Instruct",
  base_url = "http://localhost:8000/v1"
)
classifier <- llm_classifier(backend)

result <- classify(
  classifier,
  text = "I love this product!",
  choices = c("positive", "negative", "neutral")
)
```

### SGLang

```r
backend <- sglang_backend(
  model = "meta-llama/Llama-3.2-3B-Instruct",
  base_url = "http://localhost:30000/v1"
)
classifier <- llm_classifier(backend)
```

### llama.cpp

```r
backend <- llamacpp_backend(
  model = "model",
  base_url = "http://localhost:8080/v1"
)
classifier <- llm_classifier(backend)
```

## Choosing a Scoring Method

rollama provides two scoring methods, each returning a
`classification_result`. Pick based on your accuracy, latency, and
budget needs.

| | `generate()` | `classify()` |
|---|---|---|
| **Strategy** | Adaptive trie-masked generation | Multi-call completion scoring |
| **API calls** | 1 to `max_calls` (budget-controlled) | N calls for N labels |
| **Confidence** | Divergence-aware; exact when fully resolved | Always exact (calibrated) |
| **Normalization** | Geometric mean of per-token logprobs | Geometric mean of per-token logprobs |
| **`approximate`** | `TRUE` if any label has partial coverage | Always `FALSE` |
| **`method`** | `"adaptive_generate"` | `"multi_call"` |
| **Best for** | Low latency, limited call budget, or large label sets | Maximum calibration accuracy |

### `max_calls` — controlling the `generate()` budget

The `max_calls` argument controls how `generate()` spends its API budget:

| `max_calls` | Behavior | When to use |
|---|---|---|
| `1` (default) | Single constrained call; fast, may be approximate | Quick lookups, large label sets |
| `K` (integer) | Adaptive: resolves ambiguity up to K calls | Balance of speed and accuracy |
| `NULL` | Resolves all labels; exact | When you need full coverage |

```r
# Fast, single-call prediction (may be approximate)
result <- generate(classifier, text = txt, choices = choices, max_calls = 1)

# Adaptive: spend up to 3 calls to resolve ambiguities
result <- generate(classifier, text = txt, choices = choices, max_calls = 3)

# Exact: resolve every label fully
result <- generate(classifier, text = txt, choices = choices, max_calls = NULL)
```

When a result is approximate, inspect `result$coverage` (a named numeric
vector of per-label token coverage, 0.0–1.0) and `result$approximate`.

## Usage

### Basic Classification

```r
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

```r
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

```r
result <- classify(
  classifier,
  text = "The quarterly earnings exceeded analyst expectations.",
  choices = c("bullish", "bearish", "neutral"),
  system_prompt = "You are a financial sentiment analyzer.
                   Classify financial news based on market sentiment."
)
```

### Adaptive Generation (`generate()`)

`generate()` returns a `classification_result` with a calibrated
probability distribution reconstructed from constrained generation:

```r
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
print(result$coverage)    # per-label token coverage
print(result$n_calls)     # number of API calls made
```

### Batch Processing

Both methods have batch variants that return a list of
`classification_result` objects:

```r
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

## Inference Backends

### Backend Configuration

All backends share common configuration options:

| Parameter    | Default          | Description                                |
|--------------|------------------|--------------------------------------------|
| `model`      | *(required)*     | Model identifier                           |
| `base_url` / `host` | Engine-specific | Base URL of the inference server    |
| `api_key`    | `"not-needed"`   | API key for authentication                 |
| `timeout`    | `120`            | Request timeout in seconds                 |
| `max_tokens` | `256`            | Maximum tokens to generate                 |
| `extra_body` | `{}`             | Extra parameters merged into every request |

### Switching Backends

`llm_classifier()` exposes the **same API** regardless of which backend
you use — only the backend constructor differs:

```r
backends <- list(
  ollama  = ollama_backend("llama3.2"),
  vllm    = vllm_backend("my-model", base_url = "http://localhost:8000/v1"),
  sglang  = sglang_backend("my-model", base_url = "http://localhost:30000/v1"),
  llamacpp = llamacpp_backend("my-model", base_url = "http://localhost:8080/v1")
)

purrr::imap(backends, ~ {
  classifier <- llm_classifier(.x)
  result <- classify(classifier, "Hello world!", choices = c("a", "b", "c"))
  result$prediction
})
```

See `vignette("inference-backends", package = "rollama")` for per-backend
setup, constraint mechanisms, and capability details.

## API Reference

### `classification_result`

Both `generate()` and `classify()` (and their batch variants) return a
`classification_result` list:

```r
result$prediction      # Character: predicted label
result$confidence      # Numeric (0-1): confidence score
result$probabilities   # Named numeric: probability distribution (sums to 1)
result$method          # Character: "adaptive_generate" or "multi_call"
result$approximate     # Logical: TRUE if any label has partial coverage
result$coverage        # Named numeric: per-label token coverage (0.0-1.0)
result$n_calls         # Integer: number of API calls made
result$raw_response    # List: raw data for debugging
```

### Methods

| Function | Description |
|----------|-------------|
| `generate(text, choices, system_prompt, max_calls)` | Adaptive constrained generation with divergence-aware confidence |
| `classify(text, choices, system_prompt)` | Multi-call completion scoring with calibrated probabilities |
| `batch_generate(texts, choices, system_prompt, max_calls)` | Batch adaptive generation |
| `batch_classify(texts, choices, system_prompt)` | Batch classification |

### Parameters

- **text** (character): the text to classify
- **texts** (character vector): texts to classify (batch methods)
- **choices** (character vector or named list): labels, or labels with descriptions
- **system_prompt** (character or `NULL`): optional custom system prompt
- **max_calls** (integer or `NULL`, `generate()` only): API call budget — `1` (fast), `K` (adaptive), or `NULL` (exact)

## Sample Data

The package ships with a sample dataset of 20 customer support tickets across 4 labels (`billing`, `technical_support`, `account`, `general`):

```r
data(sample_tickets, package = "rollama")
head(sample_tickets)

# Test classification
results <- batch_classify(
  classifier,
  texts = sample_tickets$text,
  choices = c("billing", "technical_support", "account", "general")
)

predictions <- purrr::map_chr(results, "prediction")
mean(predictions == sample_tickets$expected_label)
```

## License

MIT License

## Development

This project is an R port of [ollama-classifier](https://github.com/paluigi/ollama-classifier). Looking forward to suggestions, issues, and pull requests!
