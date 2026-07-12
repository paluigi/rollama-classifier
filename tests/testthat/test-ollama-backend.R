# Unit tests for Ollama backend helpers (no server required)
#
# These cover the structural-token extraction logic used by the empirical
# forced-generation tokenize()/score() path. The synthetic logprobs
# mirror the tokenization Ollama actually emits for a {"label": "..."}
# JSON-enum constrained response.

testthat::test_that("ollama_label_token_logprobs: single-token label", {
  # Mirrors a real qwen2.5 emit: '{', ' "', 'label', '":', ' "',
  # 'sports', '"', ' }'
  logprobs <- list(
    list(token = "{", logprob = -17.726, top_logprobs = list()),
    list(token = ' "', logprob = -13.196, top_logprobs = list()),
    list(token = "label", logprob = -0.000, top_logprobs = list()),
    list(token = '":', logprob = -0.000, top_logprobs = list()),
    list(token = ' "', logprob = -0.000, top_logprobs = list()),
    list(token = "sports", logprob = -1.288, top_logprobs = list()),
    list(token = '"', logprob = -0.001, top_logprobs = list()),
    list(token = " }", logprob = -0.000, top_logprobs = list())
  )
  out <- rollama:::ollama_label_token_logprobs(logprobs, "sports")
  testthat::expect_equal(length(out), 1L)
  testthat::expect_equal(out[[1]]$token, "sports")
  testthat::expect_equal(out[[1]]$logprob, -1.288)
})

testthat::test_that("ollama_label_token_logprobs: multi-token label", {
  # '{"label": "' + 'tech' + ' support' + '" }'
  logprobs <- list(
    list(token = '{"label": "', logprob = -10.0, top_logprobs = list()),
    list(token = "tech", logprob = -0.5, top_logprobs = list()),
    list(token = " support", logprob = -0.7, top_logprobs = list()),
    list(token = '" }', logprob = -0.0, top_logprobs = list())
  )
  out <- rollama:::ollama_label_token_logprobs(logprobs, "tech support")
  testthat::expect_equal(length(out), 2L)
  testthat::expect_equal(out[[1]]$token, "tech")
  testthat::expect_equal(out[[2]]$token, " support")
})

testthat::test_that("ollama_label_token_logprobs: compact JSON (no spaces)", {
  # Compact JSON {"label":"sports"}
  logprobs <- list(
    list(token = '{"label":"', logprob = -10.0, top_logprobs = list()),
    list(token = "sports", logprob = -1.288, top_logprobs = list()),
    list(token = '"}', logprob = -0.0, top_logprobs = list())
  )
  out <- rollama:::ollama_label_token_logprobs(logprobs, "sports")
  testthat::expect_equal(length(out), 1L)
  testthat::expect_equal(out[[1]]$token, "sports")
})

testthat::test_that("ollama_label_token_logprobs: fallback skeleton filter", {
  # Label text never appears verbatim -> primary mapping fails and the
  # fallback drops structure/key tokens, keeping the rest.
  logprobs <- list(
    list(token = "{", logprob = -10.0, top_logprobs = list()),
    list(token = ' "', logprob = -10.0, top_logprobs = list()),
    list(token = "label", logprob = -0.0, top_logprobs = list()),
    list(token = '":', logprob = -0.0, top_logprobs = list()),
    list(token = ' "', logprob = -0.0, top_logprobs = list()),
    list(token = "sports", logprob = -1.288, top_logprobs = list()),
    list(token = '"', logprob = -0.0, top_logprobs = list()),
    list(token = "}", logprob = -0.0, top_logprobs = list())
  )
  out <- rollama:::ollama_label_token_logprobs(logprobs, "missing")
  # Only the non-structure token survives
  testthat::expect_equal(length(out), 1L)
  testthat::expect_equal(out[[1]]$token, "sports")
})

testthat::test_that("ollama_label_token_logprobs: empty input", {
  out <- rollama:::ollama_label_token_logprobs(list(), "sports")
  testthat::expect_equal(length(out), 0L)
})

testthat::test_that("filter_special_tokens: filters EOS tokens", {
  logprobs <- list(
    list(token = "sports", logprob = -1.0, top_logprobs = list()),
    list(token = "<|im_end|>", logprob = -0.1, top_logprobs = list()),
    list(token = "<|endoftext|>", logprob = -0.1, top_logprobs = list()),
    list(token = "finance", logprob = -0.5, top_logprobs = list())
  )
  out <- rollama:::filter_special_tokens(logprobs)
  testthat::expect_equal(length(out), 2L)
  testthat::expect_equal(out[[1]]$token, "sports")
  testthat::expect_equal(out[[2]]$token, "finance")
})
