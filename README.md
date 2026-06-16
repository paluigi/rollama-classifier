# rollama-classifier

R port of `ollama-classifier` for text classification with constrained output and confidence scoring. Supports multiple inference backends: **Ollama, vLLM, SGLang, and llama.cpp**.

## Features

- **Constrained Output**: Uses JSON schema with enum constraints to ensure only valid choices are generated
- **Confidence Scoring**: Multi-call evaluation with softmax for calibrated probabilities
- **Batch Processing**: Classify multiple texts efficiently
- **Flexible Choices**: Support for simple labels or labels with descriptions
- **Custom Prompts**: Override the default system prompt for specialized tasks
- **Multiple Backends**: Use Ollama, vLLM, SGLang, or llama.cpp as your inference engine (local or remote)

## Installation

```r
# Install from GitHub
pak::pak("paluigi/rollama-classifier")

# Or with remotes
remotes::install_github("paluigi/rollama-classifier")
```

### Prerequisites

- **Ollama backend**: [Ollama](https://ollama.com/download) installed and running, with a model pulled (e.g., `ollama pull llama3.2`)
- **vLLM backend**: A running [vLLM](https://docs.vllm.ai/) server
- **SGLang backend**: A running [SGLang](https://sglang.ai/) server
- **llama.cpp backend**: A running [llama.cpp server](https://github.com/ggerganov/llama.cpp/tree/master/examples/server)

## Quick Start

### Ollama (original backend)

```r
library(rollama)

classifier <- ollama_classifier("llama3.2")

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

> **Note:** JSON schema constraints and logprobs require llama.cpp to be
> compiled with the appropriate flags (e.g., `LLAMA_JSON_SCHEMA` and
> `LLAMA_SUPPORT_LOGPROBS`).

## Usage

### Basic Classification

```r
classifier <- ollama_classifier("llama3.2")

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

### Scoring (Multi-Call with Softmax)

Get calibrated probability distribution over all choices. Makes N API calls for N choices:

```r
result <- score(
  classifier,
  text = "The movie was fantastic!",
  choices = c("positive", "negative", "neutral")
)
```

### Generate Only (Fastest)

When you only need the prediction without confidence scores:

```r
prediction <- generate(
  classifier,
  text = "The team won the championship!",
  choices = c("sports", "finance", "politics")
)
```

### Batch Classification

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

| Parameter    | Default        | Description                                |
|--------------|----------------|--------------------------------------------|
| `model`      | *(required)*   | Model identifier                           |
| `base_url`   | Engine-specific | Base URL of the inference server           |
| `api_key`    | `"not-needed"` | API key for authentication                 |
| `timeout`    | `120`          | Request timeout in seconds                 |
| `max_tokens` | `256`          | Maximum tokens to generate                 |
| `extra_body` | `{}`           | Extra parameters merged into every request |

### Switching Backends

The `llm_classifier()` exposes the **same API** regardless of which backend you use:

```r
backends <- list(
  vllm = vllm_backend("my-model", base_url = "http://localhost:8000/v1"),
  sglang = sglang_backend("my-model", base_url = "http://localhost:30000/v1"),
  llamacpp = llamacpp_backend("my-model", base_url = "http://localhost:8080/v1")
)

purrr::imap(backends, ~ {
  classifier <- llm_classifier(.x)
  result <- classify(classifier, "Hello world!", choices = c("a", "b", "c"))
  result$prediction
})
```

## API Reference

### ClassificationResult

```r
# A list with components:
result$prediction       # Character: predicted label
result$confidence      # Numeric (0-1): confidence score
result$probabilities    # Named numeric: probability distribution
result$raw_response     # List: raw API response for debugging
```

### Methods

Both `ollama_classifier()` and `llm_classifier()` expose the same methods:

| Function | Description |
|----------|-------------|
| `generate(text, choices, system_prompt)` | Constrained output only (fastest) |
| `score(text, choices, system_prompt)` | Multi-call evaluation with softmax |
| `classify(text, choices, system_prompt)` | Full classification with confidence scores |
| `batch_generate(texts, choices, system_prompt)` | Batch constrained output |
| `batch_score(texts, choices, system_prompt)` | Batch scoring |
| `batch_classify(texts, choices, system_prompt)` | Batch classification |

### Parameters

- **text** (character): The text to classify
- **texts** (character vector): Texts to classify (batch methods)
- **choices** (character vector or named list): Labels, or labels with descriptions
- **system_prompt** (character or `NULL`): Optional custom system prompt

## Choosing a Method

| Use Case | Recommended Method |
|----------|-------------------|
| Speed is critical, no confidence needed | `generate()` |
| Accurate confidence scores | `classify()` / `score()` |
| Batch processing | `batch_classify()` or `batch_score()` |

## Sample Data

The package ships with a sample dataset of 20 customer support tickets across 4 labels (`billing`, `technical_support`, `account`, `general`):

```r
data(sample_tickets, package = "rollama")
head(sample_tickets)

# Test classification
predictions <- batch_generate(
  classifier,
  texts = sample_tickets$text,
  choices = c("billing", "technical_support", "account", "general")
)

mean(predictions == sample_tickets$expected_label)
```

## License

MIT License

## Development

This project is an R port of [ollama-classifier](https://github.com/paluigi/ollama-classifier). Looking forward to suggestions, issues, and pull requests!
