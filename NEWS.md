# rollama Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-07-18

**Behavior change:** `generate()` cluster resolution was rewritten to use
**hierarchical reproportioning** instead of mixing logprobs from different
constraint contexts. This fixes a critical bug where increasing `max_calls`
could *decrease* classification accuracy.

This release aligns rollama with
[ollama-classifier v0.6.0](https://github.com/paluigi/ollama-classifier/blob/main/docs/changelog.rst).

### Fixed

- **Critical:** `generate()` with `max_calls > 1` could produce *worse*
  predictions than `max_calls = 1`. Supplementary constrained calls (to
  resolve label clusters) changed the constraint set, placing their logprobs
  in a different probability space. Mixing these into the geometric mean
  corrupted the score ranking — post-mask logprobs (≈0.0) inflated the
  scores of labels with many unscored tokens. In the Python benchmark,
  accuracy dropped monotonically from 73.8% (`mc = 1`) to 50.9%
  (`mc = 8`) for the "names only" configuration.

  **Fix:** Supplementary calls now only *reproportion* probability mass
  *within* a cluster of labels, never changing between-group totals. The
  cluster's total probability (from the initial call) is redistributed
  among its members using softmax of geometric-mean scores from the subset
  call. This guarantees accuracy never degrades with increasing `max_calls`.

### Changed

- `generate()` rewritten with the reproportion approach. The BFS
  cluster-resolution loop is retained, but supplementary calls only resolve
  multi-label clusters (≥2 labels). Single-label clusters with partial
  coverage are skipped — their probability is already fixed by the
  between-group distribution, and no reproportioning call would change it.
- `max_calls = 1` now means "no cluster resolution" (single call, purely
  divergence-based scoring from the initial constrained call).
- The `raw_response` list of `generate()` now always includes
  `step_logprobs` and `scored_lengths`. The `raw_response` of `classify()`
  now always includes `token_logprobs`.
- Function docstrings updated to reflect the hierarchical reproportion
  algorithm.

### Added

- `tests/testthat/helper-mock-backend.R` — a `MockBackend` for offline
  testing of `generate()`/`classify()` (no inference server required).
- `tests/testthat/test-classifier.R` — unit tests for `generate()` /
  `classify()` / batch variants, plus three regression tests ported from
  `ollama-classifier` v0.6.0 `TestMaxCallsMonotonicity` verifying that:
  (1) increasing `max_calls` never flips a correct prediction,
  (2) between-group probability mass is preserved during reproportioning,
  and (3) single-token labels require no resolution calls.

## [0.5.0] - 2026-07-12

**Behavior change:** All four backends were rewritten with a unified
architecture: `tokenize()` uses empirical forced constrained generation
across all backends, and `score()` uses echo/prefill (vLLM, SGLang) or
forced constrained generation (Ollama, llama.cpp) depending on server
capabilities. This is a minor version bump because the `score()` /
`classify()` contract and per-call cost change.

### Fixed

- `ollama_score()` no longer uses `/api/generate` with `suffix` (HTTP 400
  "does not support insert" on instruct models). Now uses forced
  constrained generation via JSON Schema enum.
- `ollama_tokenize()` no longer calls the removed `/api/tokenize`
  endpoint (was an error on modern Ollama). All backends' `tokenize()`
  now use forced constrained generation so token boundaries match actual
  constrained-generation output. Results are memoized per label.
- `sglang_backend()` `score()` rewritten to use echo/prefill
  (`/v1/completions` with `echo = TRUE`) with the correct `"prompt"`
  field in `/tokenize` for boundary detection. Produces differentiated
  confidence for `classify()` (was near-uniform with forced generation
  due to prompt-priming).
- `sglang_backend()` `tokenize()` no longer sends the wrong field name
  (`"text"` vs the API's `"prompt"`). Now uses forced constrained
  generation via regex.
- `vllm_backend()` constraint updated from deprecated `guided_choice`
  (removed in vLLM v0.12.0) to `structured_outputs.choice`. `score()`
  rewritten to use echo/prefill; `tokenize()` uses forced constrained
  generation.
- `llamacpp_backend()` `score()` rewritten from broken `suffix`-based
  completions to forced GBNF grammar generation (llama.cpp does not
  support `echo = TRUE` on the completions endpoint).
- All backends: `score()` now raises an error when no value tokens are
  returned (previously returned empty logprobs silently).

### Changed

- **Behavior change:** `score()` now uses echo/prefill (vLLM, SGLang) or
  forced constrained generation (Ollama, llama.cpp), not a no-generation
  forward pass.
- `tokenize()` return value is now always token *strings* (empirical
  tokens have no stable server-side ID). Downstream consumers should not
  rely on token IDs.
- All backend docstrings updated to document the scoring and
  tokenization mechanisms.

### Added

- `ollama_label_token_logprobs()` — extracts label-value tokens from a
  `{"label": "..."}` response via char-offset span mapping.
- `filter_special_tokens()` and `SPECIAL_TOKENS` — filter special/EOS
  tokens from bare-label responses (Llama-3, Phi, Qwen EOS markers).
- `omni_forced_score()` — shared forced constrained generation score
  helper for llama.cpp.
- `omni_forced_tokenize()` — shared forced constrained generation
  tokenize helper for vLLM, SGLang, llama.cpp.
- Token memoization caches in all backends (per-label, amortizes
  forced-generation setup cost).
- `local_tests/` — integration test infrastructure with dataset
  evaluation and CSV output for all four backends.
- `tests/testthat/test-ollama-backend.R` — unit tests for the Ollama
  label-token extraction helper (no server required).

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
