# MockBackend — deterministic backend for unit testing.
#
# Ported from ollama-classifier v0.6.0 tests/conftest.py.
# Simulates constrained generation and completion scoring without a real
# LLM server. Returns deterministic responses based on pre-configured label
# token sequences and step logprobs.
#
# chat() returns the first label of `constrain_labels` as the winner
# (deterministic for testing). The configured `step_logprobs_map[[winner]]`
# provides the per-step top_logprobs that drive divergence-aware scoring.

new_mock_backend <- function(label_tokens = list(),
                              step_logprobs_map = list(),
                              completion_logprobs = list(),
                              bare_labels = TRUE) {
  call_count <- 0L

  chat_fn <- function(messages, temperature = 0, constrain_labels = NULL,
                       logprobs = FALSE, top_logprobs = 5) {
    call_count <<- call_count + 1L
    labels <- constrain_labels %||% names(label_tokens)
    # Winner = first label in the constraint set (deterministic)
    winner <- labels[[1L]]
    step_lps <- step_logprobs_map[[winner]] %||% list()

    logprobs_out <- purrr::map(step_lps, function(step_lp) {
      best_token <- names(step_lp)[[which.max(step_lp)]]
      list(
        token = best_token,
        logprob = step_lp[[best_token]],
        top_logprobs = as.list(step_lp)
      )
    })

    list(content = winner, label = winner, logprobs = logprobs_out)
  }

  score_fn <- function(messages, completion) {
    call_count <<- call_count + 1L
    lps <- completion_logprobs[[completion]] %||% -1.0
    list(
      completion = completion,
      logprobs = purrr::map(lps, ~ list(token = "x", logprob = .x))
    )
  }

  tokenize_fn <- function(text, context = NULL) {
    label_tokens[[text]] %||% text
  }

  structure(
    list(
      chat = chat_fn,
      score = score_fn,
      tokenize = tokenize_fn,
      model = "mock",
      base_url = "http://mock",
      supports_bare_label_constraint = bare_labels,
      call_count = function() call_count
    ),
    class = c("mock_backend", "llm_backend")
  )
}

# Fixtures mirroring the Python conftest.py -------------------------------

mock_backend_single_token <- function() {
  new_mock_backend(
    label_tokens = list(
      positive  = "positive",
      negative  = "negative",
      neutral   = "neutral"
    ),
    step_logprobs_map = list(
      positive = list(c(positive = -0.3, negative = -1.5, neutral = -2.8))
    ),
    completion_logprobs = list(
      positive = -0.3,
      negative = -1.5,
      neutral  = -2.8
    )
  )
}

mock_backend_multi_token <- function() {
  new_mock_backend(
    label_tokens = list(
      a = c("t1", "t2", "t3", "t4a"),
      b = c("t1", "t2", "t3", "t4b"),
      c = c("t1c", "t2c", "t3c", "t4c")
    ),
    step_logprobs_map = list(
      # Winner a: b diverges at pos 4, c at pos 1
      a = list(
        c(t1 = -0.1, t1c = -2.5),
        c(t2 = -0.2, x  = -3.0),
        c(t3 = -0.15, y = -2.8),
        c(t4a = -0.1, t4b = -1.5)
      ),
      # Winner b: a diverges at pos 4
      b = list(
        c(t1 = -0.1, t1c = -2.5),
        c(t2 = -0.2, x  = -3.0),
        c(t3 = -0.15, y = -2.8),
        c(t4b = -0.1, t4a = -1.0)
      )
    ),
    completion_logprobs = list(
      a = c(-0.1, -0.2, -0.15, -0.1),
      b = c(-0.1, -0.2, -0.15, -1.5),
      c = c(-2.5, -0.2, -0.15, -0.1)
    )
  )
}
