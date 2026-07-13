# Inference Backends

## Overview

`rollama` supports four inference backends, all accessed through the
same
[`llm_classifier()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llm_classifier.md)
interface. Each backend is created by a constructor function and exposes
a unified set of methods: `chat()`, `score()`, and `tokenize()`.

``` r
library(rollama)

backend   <- ollama_backend("llama3.2")   # or vllm / sglang / llamacpp
classifier <- llm_classifier(backend)
```

Because the classifier talks to backends through this common interface,
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md),
[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md),
and their batch variants work identically no matter which engine you
use. The backends differ only in how they run and how they constrain
output to valid labels.

## Backend capabilities and label constraints

Every backend constrains the model’s generation to one of the supplied
labels so that
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)
always produces a valid choice. The mechanism differs per engine,
captured by the `supports_bare_label_constraint` flag:

| Backend                                                                                                   | `supports_bare_label_constraint` | Constraint mechanism                        | Output form        |
|-----------------------------------------------------------------------------------------------------------|----------------------------------|---------------------------------------------|--------------------|
| [`ollama_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/ollama_backend.md)     | `FALSE`                          | JSON Schema `enum` (via `format`)           | `{"label": "..."}` |
| [`vllm_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/vllm_backend.md)         | `TRUE`                           | `structured_outputs.choice` (vLLM v0.12.0+) | bare label text    |
| [`sglang_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/sglang_backend.md)     | `TRUE`                           | `regex`                                     | bare label text    |
| [`llamacpp_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llamacpp_backend.md) | `TRUE`                           | GBNF `grammar`                              | bare label text    |

Backends with `supports_bare_label_constraint = TRUE` emit the label as
plain text. The Ollama backend wraps the label in a small JSON object
(`{"label": "<chosen>"}`); `rollama` filters the structural JSON tokens
during trie reconstruction and uses context-dependent tokenization so
the prefix trie matches the actual response tokens. This is an internal
detail — both paths feed the same
[`generate()`](https://paluigi-moltis.github.io/rollama-classifier/reference/generate.md)
/
[`classify()`](https://paluigi-moltis.github.io/rollama-classifier/reference/classify.md)
logic.

### Scoring and tokenization

All backends share a unified approach:

- **`tokenize()`** uses empirical *forced constrained generation* —
  forcing the label as the only valid choice in a `chat()` call and
  reading back the emitted value tokens. This is necessary because
  standalone BPE tokenization produces different token boundaries than
  the model emits under constraint guidance, which would break
  trie-based divergence scoring. Results are memoized per label.
- **`score()`** uses one of two mechanisms depending on server
  capabilities:
  - **Echo/prefill** (vLLM, SGLang): `/v1/completions` with `echo=TRUE`
    to recover the model’s genuine per-token logprobs for the label as
    an unexpected continuation of the prompt. The `/tokenize` endpoint
    pinpoints the label-token boundary.
  - **Forced constrained generation** (Ollama, llama.cpp): forces the
    label as the only valid choice and reads back the model’s genuine
    per-token logprobs (teacher forcing). Used when the server does not
    support `echo=TRUE` (llama.cpp) or fill-in-the-middle (Ollama).

## Ollama

The default backend. Uses the native Ollama REST API (`/api/chat`).
Requires the Ollama runtime (\>=v0.12) installed locally.

Modern Ollama removed the `/api/tokenize` endpoint and does not support
fill-in-the-middle (“insert”) on instruct models. This backend therefore
obtains both label tokenization and completion scores through empirical
*forced constrained generation*: it forces a label as the only valid
choice in a `chat()` call and reads back the model’s genuine per-token
logprobs. Tokenization results are memoized per label to amortize the
cost.

**Start:**

``` bash
ollama pull llama3.2
ollama serve
```

**Connect:**

``` r
backend <- ollama_backend(model = "llama3.2")
classifier <- llm_classifier(backend)
```

[`ollama_backend()`](https://paluigi-moltis.github.io/rollama-classifier/reference/ollama_backend.md)
defaults to `host = "http://localhost:11434"`. To point at a remote
Ollama instance, set `host`:

``` r
backend <- ollama_backend(
  model = "llama3.2",
  host  = "https://my-ollama.example.com"
)
```

Ollama constrains labels with a JSON Schema `enum` passed via the
`format` parameter, so it sets `supports_bare_label_constraint = FALSE`.

## vLLM

High-throughput serving engine for LLMs. Communicates via the
OpenAI-compatible API and supports `structured_outputs.choice` (vLLM
v0.12.0+) and logprobs out of the box.

`score()` uses echo/prefill (`/v1/completions` with `echo=TRUE`) to
recover genuine per-label logprobs. `tokenize()` uses forced constrained
generation via `structured_outputs.choice` so token boundaries match the
actual constrained-generation output. Results are memoized per label.

**Start a local server:**

``` bash
vllm serve Qwen/Qwen2.5-3B-Instruct --host 0.0.0.0 --port 8000
```

**Connect:**

``` r
backend <- vllm_backend(
  model = "meta-llama/Llama-3.2-3B-Instruct",
  base_url = "http://localhost:8000/v1"
)
classifier <- llm_classifier(backend)
```

vLLM constrains labels natively with `structured_outputs.choice`
(replaces the deprecated `guided_choice` removed in vLLM v0.12.0),
producing bare label text, so `supports_bare_label_constraint = TRUE`.

**Remote server:**

``` r
backend <- vllm_backend(
  model = "your-model",
  base_url = "https://your-vllm-server.com/v1",
  api_key = "your-api-key"
)
classifier <- llm_classifier(backend)
```

## SGLang

Fast serving system for large language models with efficient radix
attention. Also OpenAI-compatible.

`score()` uses echo/prefill (`/v1/completions` with `echo=TRUE`) to
recover genuine per-label logprobs. The `/tokenize` endpoint (with the
correct `"prompt"` field) pinpoints the label-token boundary.
`tokenize()` uses forced constrained generation via regex so token
boundaries match the actual constrained-generation output. Results are
memoized per label.

**Start a local server:**

``` bash
python -m sglang.launch_server \
    --model-path meta-llama/Llama-3.2-3B-Instruct \
    --host 0.0.0.0 --port 30000
```

**Connect:**

``` r
backend <- sglang_backend(
  model = "meta-llama/Llama-3.2-3B-Instruct",
  base_url = "http://localhost:30000/v1"
)
classifier <- llm_classifier(backend)
```

SGLang constrains labels with a `regex` built from the label set
(`(label1|label2|...)`), producing bare label text, so
`supports_bare_label_constraint = TRUE`.

## llama.cpp

Lightweight inference via `llama-server`. Ideal for CPU or mixed CPU/GPU
environments.

Both `score()` and `tokenize()` use forced constrained generation via
GBNF grammar because llama.cpp does **not** support `echo=TRUE` on the
completions endpoint (it only returns generated-token logprobs, not
prompt tokens), so the echo/prefill approach used by vLLM and SGLang is
unavailable. Results are memoized per label.

**Start a local server:**

``` bash
./llama-server -m model.gguf --host 0.0.0.0 --port 8080 -c 4096
```

**Connect:**

``` r
backend <- llamacpp_backend(
  model = "model",
  base_url = "http://localhost:8080/v1"
)
classifier <- llm_classifier(backend)
```

llama.cpp constrains labels with a GBNF `grammar`
(`root ::= "label1" | "label2" | "label3"`), producing bare label text,
so `supports_bare_label_constraint = TRUE`.

> **Note:** Logprobs support requires `llama-server` to be compiled with
> the appropriate flag (e.g. `LLAMA_SUPPORT_LOGPROBS`). Constrained
> generation via grammar is available in recent llama.cpp builds.

## Backend Configuration

All backends share common configuration options:

| Parameter           | Default                                   | Description                                |
|---------------------|-------------------------------------------|--------------------------------------------|
| `model`             | *(required)*                              | Model identifier                           |
| `base_url` / `host` | Engine-specific                           | Base URL of the inference server           |
| `api_key`           | `"not-needed"`                            | API key for authentication                 |
| `timeout`           | `120`                                     | Request timeout in seconds                 |
| `max_tokens`        | `256`                                     | Maximum tokens to generate                 |
| `extra_body`        | [`{}`](https://rdrr.io/r/base/Paren.html) | Extra parameters merged into every request |

> Ollama uses `host` instead of `base_url` and has no `api_key`
> parameter (the native API needs none). The other backends use
> `base_url` and `api_key` to match the OpenAI-compatible convention.

## Switching Backends

[`llm_classifier()`](https://paluigi-moltis.github.io/rollama-classifier/reference/llm_classifier.md)
exposes the **same API** regardless of which backend you use — only the
constructor differs:

``` r
backends <- list(
  ollama   = ollama_backend("llama3.2"),
  vllm     = vllm_backend("my-model", base_url = "http://localhost:8000/v1"),
  sglang   = sglang_backend("my-model", base_url = "http://localhost:30000/v1"),
  llamacpp = llamacpp_backend("my-model", base_url = "http://localhost:8080/v1")
)

purrr::imap(backends, ~ {
  classifier <- llm_classifier(.x)
  result <- classify(classifier, "Hello world!", choices = c("a", "b", "c"))
  paste0(.y, ": ", result$prediction)
})
```

## Inspecting a backend

Every backend is a list with the unified methods plus capability
metadata. This is primarily useful for debugging or advanced use:

``` r
backend <- ollama_backend("llama3.2")

backend$chat        # constrained chat completion
backend$score       # completion scoring (used by classify())
backend$tokenize    # context-dependent tokenization
backend$supports_bare_label_constraint  # FALSE for Ollama, TRUE elsewhere
```
