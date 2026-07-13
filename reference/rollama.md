# rollama: Classify Text with LLMs on Ollama and Other Backends

A wrapper around the Ollama REST API and other inference engines (vLLM,
SGLang, llama.cpp) for text classification with constrained output and
confidence scoring. All backends use empirical forced constrained
generation for tokenization and echo/prefill or forced generation for
completion scoring. Provides two scoring methods:

- [`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md):
  Adaptive constrained generation with divergence-aware confidence
  scoring, budget-controlled via `max_calls`.

- [`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md):
  Multi-call completion scoring with geometric-mean normalization.
  Gold-standard accuracy.

## Features

- Adaptive constrained generation with trie-based confidence scoring

- Multi-call completion scoring with geometric-mean normalization

- Eliminates confidence concentration bias from raw logprob sums

- Support for multiple inference backends: Ollama, vLLM, SGLang,
  llama.cpp

- Batch processing for multiple texts

- Support for simple labels or labels with descriptions

## Quick Start

    backend <- ollama_backend("llama3.2")
    classifier <- llm_classifier(backend)

    result <- classify(
      classifier,
      text = "I love this product!",
      choices = c("positive", "negative", "neutral")
    )
    print(result$prediction)
    print(result$confidence)

## Choosing a Scoring Method

|                                                                                           |           |              |                       |
|-------------------------------------------------------------------------------------------|-----------|--------------|-----------------------|
| Method                                                                                    | API Calls | Exactness    | When to Use           |
| `generate(max_calls = 1)`                                                                 | 1         | Approximate  | Speed-critical        |
| `generate(max_calls = NULL)`                                                              | 1-N       | Exact        | Adaptive resolution   |
| [`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md) | N         | Always exact | Research, calibration |

## References

<https://github.com/paluigi/rollama-classifier>

## See also

Useful links:

- <https://github.com/paluigi/rollama-classifier>

- <https://paluigi-moltis.github.io/rollama-classifier/>

- Report bugs at <https://github.com/paluigi/rollama-classifier/issues>

## Author

Luigi Palumbo <paluigi@users.noreply.github.com>, Mengting Yu, Carolina
Camassa
