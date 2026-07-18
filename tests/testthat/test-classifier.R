# Unit tests for the llm_classifier generate() and classify() methods.
#
# Ports three regression tests from ollama-classifier v0.6.0
# (tests/test_classifier.py::TestMaxCallsMonotonicity), plus structural
# checks for generate()/classify(). All tests run against the MockBackend
# defined in helper-mock-backend.R — no inference server required.

# =========================================================================
# TestGenerate — basic generate() contract
# =========================================================================

testthat::test_that("generate returns a classification_result", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- generate(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_s3_class(result, "classification_result")
  testthat::expect_true(result$prediction %in% c("positive", "negative", "neutral"))
})

testthat::test_that("generate confidence is in [0, 1]", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- generate(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_gte(result$confidence, 0)
  testthat::expect_lte(result$confidence, 1)
})

testthat::test_that("generate probabilities sum to 1", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- generate(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_equal(sum(result$probabilities), 1.0, tolerance = 1e-10)
})

testthat::test_that("generate single-token labels are exact (n_calls == 1)", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- generate(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_equal(result$prediction, "positive")
  testthat::expect_equal(result$n_calls, 1L)
  testthat::expect_false(isTRUE(result$approximate))
})

testthat::test_that("generate multi-token: max_calls limits calls", {
  clf <- llm_classifier(mock_backend_multi_token())
  result <- generate(clf, "text", c("a", "b", "c"), max_calls = 1L)
  testthat::expect_lte(result$n_calls, 1L)
})

testthat::test_that("generate with named-list choices works", {
  clf <- llm_classifier(mock_backend_single_token())
  choices <- list(positive = "happy", negative = "sad", neutral = "meh")
  result <- generate(clf, "text", choices)
  testthat::expect_s3_class(result, "classification_result")
  testthat::expect_setequal(names(result$probabilities), c("positive", "negative", "neutral"))
})

# =========================================================================
# TestClassify — classify() contract
# =========================================================================

testthat::test_that("classify returns a classification_result", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- classify(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_s3_class(result, "classification_result")
})

testthat::test_that("classify probabilities sum to 1", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- classify(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_equal(sum(result$probabilities), 1.0, tolerance = 1e-10)
})

testthat::test_that("classify makes N calls for N labels", {
  backend <- mock_backend_single_token()
  clf <- llm_classifier(backend)
  classify(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_equal(backend$call_count(), 3L)
})

testthat::test_that("classify raw_response includes token_logprobs", {
  clf <- llm_classifier(mock_backend_single_token())
  result <- classify(clf, "text", c("positive", "negative", "neutral"))
  testthat::expect_false(is.null(result$raw_response$token_logprobs))
  testthat::expect_setequal(
    names(result$raw_response$token_logprobs),
    c("positive", "negative", "neutral")
  )
})

# =========================================================================
# TestBatch
# =========================================================================

testthat::test_that("batch_generate returns a list of results", {
  clf <- llm_classifier(mock_backend_single_token())
  results <- batch_generate(
    clf, c("t1", "t2"), c("positive", "negative", "neutral")
  )
  testthat::expect_length(results, 2L)
  testthat::expect_s3_class(results[[1]], "classification_result")
})

testthat::test_that("batch_classify returns a list of results", {
  clf <- llm_classifier(mock_backend_single_token())
  results <- batch_classify(
    clf, c("t1", "t2"), c("positive", "negative", "neutral")
  )
  testthat::expect_length(results, 2L)
  testthat::expect_s3_class(results[[1]], "classification_result")
})

# =========================================================================
# TestMaxCallsMonotonicity — regression tests for hierarchical reproportion.
# Ported from ollama-classifier v0.6.0 tests/test_classifier.py.
#
# The original cluster-resolution code mixed logprobs from different
# constraint contexts into a single geometric mean, which could DECREASE
# accuracy as max_calls increased. The fix uses reproportioning:
# supplementary calls only redistribute probability mass *within* a cluster,
# never changing between-group totals.
# =========================================================================

# Shared fixture for the monotonicity tests.
# Scenario: 3 labels with a shared prefix.
#   A = [shared, a_end]                   (2 tokens)
#   B = [shared, b_mid, b1, b2, b3]       (5 tokens, diverges at token 2)
#   C = [c_first, c_end]                  (2 tokens, diverges at token 1)
#
# The MockBackend returns labels[1] as winner for any constraint set, so
#   - 3-way call:  winner = "A"
#   - 1-way call on ["B"]: winner = "B"
#   - 1-way call on ["C"]: winner = "C"
#   - 2-way call on ["A","B"]: winner = "A"
monotonicity_label_tokens <- list(
  A = c("shared", "a_end"),
  B = c("shared", "b_mid", "b1", "b2", "b3"),
  C = c("c_first", "c_end")
)

monotonicity_step_logprobs <- list(
  A = list(
    c(shared = -0.3, c_first = -1.5),
    c(a_end = -0.1, b_mid = -0.6)
  ),
  B = list(
    c(shared = -0.3),
    c(b_mid = -0.6),
    c(b1 = -0.5),
    c(b2 = -0.5),
    c(b3 = -0.5)
  ),
  C = list(
    c(c_first = -1.5),
    c(c_end = -0.3)
  )
)

monotonicity_completion_logprobs <- list(
  A = c(-0.3, -0.1),
  B = c(-0.3, -0.6, -0.5, -0.5, -0.5),
  C = c(-1.5, -0.3)
)

testthat::test_that("max_calls does not flip a correct prediction", {
  # generate(max_calls = NULL) must not produce a worse prediction than
  # generate(max_calls = 1). The model's true preference is A > B > C, and
  # greedy constrained generation picks A. Reproportioning must not inflate
  # B's probability above A's.
  predictions <- list()
  for (mc in list(1L, 2L, 3L, NULL)) {
    key <- if (is.null(mc)) "NULL" else as.character(mc)
    backend <- new_mock_backend(
      label_tokens = monotonicity_label_tokens,
      step_logprobs_map = monotonicity_step_logprobs,
      completion_logprobs = monotonicity_completion_logprobs,
      bare_labels = TRUE
    )
    clf <- llm_classifier(backend)
    result <- generate(clf, "test", c("A", "B", "C"), max_calls = mc)
    predictions[[key]] <- result$prediction
    # Probabilities must always sum to 1.0
    testthat::expect_equal(
      sum(result$probabilities), 1.0, tolerance = 1e-10,
      label = paste0("max_calls=", key, ": probabilities must sum to 1.0")
    )
  }

  # All predictions must be "A" (the correct answer)
  for (mc in names(predictions)) {
    testthat::expect_equal(
      predictions[[mc]], "A",
      label = paste0("max_calls=", mc, ": expected 'A', got '", predictions[[mc]], "'")
    )
  }
})

testthat::test_that("reproportion preserves between-group mass", {
  # The sum of cluster probabilities is invariant under reproportioning.
  # Concretely: A's probability must not decrease when max_calls grows.
  backend1 <- new_mock_backend(
    label_tokens = monotonicity_label_tokens,
    step_logprobs_map = monotonicity_step_logprobs,
    bare_labels = TRUE
  )
  clf1 <- llm_classifier(backend1)
  result1 <- generate(clf1, "test", c("A", "B", "C"), max_calls = 1L)

  backend2 <- new_mock_backend(
    label_tokens = monotonicity_label_tokens,
    step_logprobs_map = monotonicity_step_logprobs,
    bare_labels = TRUE
  )
  clf2 <- llm_classifier(backend2)
  result2 <- generate(clf2, "test", c("A", "B", "C"), max_calls = NULL)

  # Both distributions sum to 1.0
  testthat::expect_equal(sum(result1$probabilities), 1.0, tolerance = 1e-10)
  testthat::expect_equal(sum(result2$probabilities), 1.0, tolerance = 1e-10)

  # A's probability must not decrease under full resolution
  testthat::expect_gte(
    result2$probabilities[["A"]],
    result1$probabilities[["A"]] - 1e-10,
    label = paste0(
      "A's probability decreased: mc=1=", result1$probabilities[["A"]],
      ", mc=NULL=", result2$probabilities[["A"]]
    )
  )
})

testthat::test_that("single-token labels need no resolution calls", {
  # When all labels are single-token, max_calls has no effect — there are no
  # clusters to resolve.
  label_tokens <- list(
    positive  = "positive",
    negative  = "negative",
    neutral   = "neutral"
  )
  step_logprobs_map <- list(
    positive = list(c(positive = -0.3, negative = -1.5, neutral = -2.8))
  )

  for (mc in list(1L, 5L, NULL)) {
    backend <- new_mock_backend(
      label_tokens = label_tokens,
      step_logprobs_map = step_logprobs_map,
      bare_labels = TRUE
    )
    clf <- llm_classifier(backend)
    result <- generate(clf, "test", c("positive", "negative", "neutral"),
                        max_calls = mc)
    testthat::expect_equal(result$prediction, "positive")
    testthat::expect_equal(result$n_calls, 1L)  # no resolution calls
    testthat::expect_false(isTRUE(result$approximate))
  }
})
