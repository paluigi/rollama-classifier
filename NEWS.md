# rollama Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-07-06

The v0.4.0 redesign unifies the package around a single
`llm_classifier()` backed by four unified backends, each exposing the
same `chat()`, `score()`, and `tokenize()` methods. It introduces two
clearly distinct scoring methods — adaptive `generate()` and exact
`classify()` — both returning a rich `classification_result`.

### Added

- `ollama_backend()` — unified Ollama backend with `chat()`, `score()`,
  and `tokenize()` methods, replacing the special-cased Ollama path.
  All four backends now share the same interface.
- Adaptive `generate()` with the `max_calls` parameter for budget
  control: `1` (single fast call, possibly approximate), `K` (adaptive
  resolution up to K calls), or `NULL` (resolve all labels, exact).
- New `classification_result` fields: `coverage` (named numeric vector
  of per-label token coverage, 0.0–1.0), `n_calls` (API calls made),
  `approximate` (logical), and `method` (`"adaptive_generate"` or
  `"multi_call"`).
- New `R/scoring.R` module: shared scoring utilities used by both
  `generate()` and `classify()`, including a label prefix trie and
  divergence-aware scoring.
- Geometric-mean length normalization (`geometric_mean_logprob()`)
  applied consistently across both scoring methods.
- `supports_bare_label_constraint` capability flag on every backend,
  indicating whether the engine can emit bare label text (vLLM, SGLang,
  llama.cpp) or wraps labels in JSON (Ollama).

### Changed

- **BREAKING:** `generate()` now returns a `classification_result` (with
  `prediction`, `confidence`, `probabilities`, `method`, `approximate`,
  `coverage`, `n_calls`). In 0.3.0 it returned a bare predicted string.
- **BREAKING:** `llm_classifier()` is now the single entry point for all
  backends, including Ollama. It takes a backend object created by
  `ollama_backend()`, `vllm_backend()`, `sglang_backend()`, or
  `llamacpp_backend()`.
- `classify()` rewritten: uses multi-call completion scoring
  (`backend$score()`) with geometric-mean normalization instead of the
  previous softmax-over-summed-logprobs approach.
- All backends rewritten around the unified `chat()` / `score()` /
  `tokenize()` interface; they now carry capability metadata.
- `batch_generate()` and `batch_classify()` return lists of
  `classification_result` objects.

### Fixed

- Concentration/length bias in confidence scoring: raw logprob sums
  favored labels with fewer tokens. Geometric-mean normalization makes
  scores comparable across labels of different lengths.
- Eliminated code duplication between the old `ollama_classifier()` and
  `llm_classifier()` paths via the unified backend interface.

### Removed

- `ollama_classifier()` function — replaced by
  `llm_classifier(ollama_backend())`.
- Old `llm_classifier()` implementation (`R/llm-backend.R`) and the
  Ollama-specific classifier (`R/ollama-classifier.R`).
- Redundant `score()` / `batch_score()` generics and S3 methods.

## [0.3.0] - 2025-06-16

### Added

- `llm_classifier()` — a generic, backend-agnostic classifier that works with any inference engine
- `vllm_backend()` — inference backend for vLLM (local and remote)
- `sglang_backend()` — inference backend for SGLang (local and remote)
- `llamacpp_backend()` — inference backend for llama.cpp server (local and remote)
- `generate()`, `classify()` and their batch variants as S3 generics
- `build_classification_prompt()`, `get_choice_labels()` as exported utilities
- `sample_tickets` dataset — 20 customer support tickets for testing
- Vignettes: "Getting Started with rollama" and "Inference Backends"
- `pkgdown` site configuration
- Full roxygen2 documentation for all functions

### Changed

- Initial R port of [ollama-classifier](https://github.com/paluigi/ollama-classifier) v0.3.0
- Uses `httr2` for HTTP (CRAN-friendly) instead of Python `httpx`
- Uses functional style with S3 dispatch instead of OOP classes
- Sample data provided as an R data frame instead of Python dataclass
