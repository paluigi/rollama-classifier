# rollama Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-06-16

### Added

- `llm_classifier()` — a generic, backend-agnostic classifier that works with any inference engine
- `vllm_backend()` — inference backend for vLLM (local and remote)
- `sglang_backend()` — inference backend for SGLang (local and remote)
- `llamacpp_backend()` — inference backend for llama.cpp server (local and remote)
- `generate()`, `score()`, `classify()` and their batch variants as S3 generics
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
