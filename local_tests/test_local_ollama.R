# LOCAL-ONLY integration tests against a real Ollama server.
#
# This file lives under local_tests/ and is NOT part of R CMD check
# (excluded via .Rbuildignore). It exercises a running local Ollama
# instance and the qwen2.5:3b-instruct model through both scoring
# methods of llm_classifier():
#
#   classify()  -- exact multi-call completion scoring (method = "multi_call")
#   generate()  -- adaptive constrained generation (method = "adaptive_generate")
#
# Prerequisites
# -------------
# 1. Ollama runtime installed and running (>=0.12):
#      https://ollama.com/download
# 2. Pull the model once:
#      ollama pull qwen2.5:3b-instruct
#
# Run with:
#   Rscript local_tests/test_local_ollama.R
#
# The whole module is skipped automatically if Ollama is unreachable or the
# model is not present, so running it never hard-fails.

library(testthat)

# Source the R package (assuming devtools::load_all() or installed package)
if (requireNamespace("rollama", quietly = TRUE)) {
  library(rollama)
} else {
  # Dev mode: load all package sources from the parent directory
  pkg_root <- normalizePath(file.path(dirname(getwd())))
  if (file.exists(file.path(pkg_root, "DESCRIPTION"))) {
    devtools::load_all(pkg_root)
  } else {
    stop("Could not find the rollama package. Run from the r-pkg directory or install the package.")
  }
}

MODEL <- "qwen2.5:3b-instruct"
HOST  <- "http://localhost:11434"
PORT  <- 11434

# ---------------------------------------------------------------------------
# Skip guards: only run against a reachable server + present model
# ---------------------------------------------------------------------------

port_open <- function(host = "localhost", port = 11434, timeout = 1.0) {
  con <- tryCatch(
    socketConnection(host = host, port = port, timeout = timeout, open = "r", blocking = TRUE),
    error = function(e) NULL
  )
  if (is.null(con)) return(FALSE)
  close(con)
  TRUE
}

model_present <- function(model = MODEL, host = HOST) {
  tryCatch({
    resp <- jsonlite::fromJSON(paste0(host, "/api/tags"), simplifyVector = FALSE)
    names <- vapply(resp$models, function(m) m$name %||% "", character(1))
    any(names == model | startsWith(names, paste0(model, ":")))
  }, error = function(e) FALSE)
}

skip_if_no_server <- function() {
  if (!port_open()) skip(paste("Ollama server not reachable at", HOST))
}

skip_if_no_model <- function() {
  if (!model_present()) skip(paste0("Model '", MODEL, "' not found; run: ollama pull ", MODEL))
}

# ---------------------------------------------------------------------------
# Shared assertions
# ---------------------------------------------------------------------------

assert_valid <- function(result, choices, method) {
  expect_s3_class(result, "classification_result")
  expect_equal(result$method, method)
  expect_true(result$prediction %in% choices)
  expect_true(result$confidence >= 0 && result$confidence <= 1)
  expect_setequal(names(result$probabilities), choices)
  expect_lt(abs(sum(result$probabilities) - 1.0), 1e-6)
}

make_classifier <- function() {
  backend <- ollama_backend(model = MODEL, host = HOST)
  llm_classifier(backend)
}

# ===========================================================================
# classify() -- exact multi-call completion scoring (N calls for N labels)
# ===========================================================================

test_that("classify: basic 4-way topic classification", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "The new quantum processor architecture drastically reduces latency."
  choices <- c("technology", "sports", "politics", "entertainment")

  result <- classify(classifier, text = text, choices = choices)

  cat("\n[classify] text=", text, "\n")
  cat("  prediction=", result$prediction, " confidence=", sprintf("%.2f%%", result$confidence * 100), "\n")

  assert_valid(result, choices, "multi_call")
  expect_false(result$approximate)
  expect_equal(result$n_calls, length(choices))
  expect_equal(result$prediction, "technology")
})

test_that("classify: with descriptions", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "This restaurant has amazing food but terrible service."
  choices <- list(
    positive = "Text expresses happiness, satisfaction, or approval",
    negative = "Text expresses anger, disappointment, or disapproval",
    mixed    = "Text contains both positive and negative sentiments",
    neutral  = "Text is factual without strong emotional content"
  )

  result <- classify(classifier, text = text, choices = choices)

  assert_valid(result, names(choices), "multi_call")
  expect_true(result$prediction %in% c("negative", "mixed"))
})

test_that("classify: custom system prompt", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "The quarterly earnings exceeded analyst expectations."
  choices <- c("bullish", "bearish", "neutral")

  result <- classify(
    classifier,
    text = text,
    choices = choices,
    system_prompt = paste("You are a financial sentiment analyzer.",
                          "Classify financial news based on market sentiment.")
  )

  assert_valid(result, choices, "multi_call")
  expect_equal(result$prediction, "bullish")
})

# ===========================================================================
# generate() -- adaptive constrained generation (1..max_calls calls)
# ===========================================================================

test_that("generate: single call (max_calls=1)", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "The team won the championship!"
  choices <- c("sports", "finance", "science", "politics")

  result <- generate(classifier, text = text, choices = choices, max_calls = 1L)

  cat("\n[generate max_calls=1] text=", text, "\n")
  cat("  prediction=", result$prediction, " approximate=", result$approximate, "\n")

  assert_valid(result, choices, "adaptive_generate")
  expect_equal(result$n_calls, 1L)
  expect_equal(result$prediction, "sports")
})

test_that("generate: adaptive budget (max_calls=3)", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "Stock prices plummeted after the announcement."
  choices <- c("sports", "finance", "science", "politics")

  result <- generate(classifier, text = text, choices = choices, max_calls = 3L)

  assert_valid(result, choices, "adaptive_generate")
  expect_gte(result$n_calls, 1L)
  expect_lte(result$n_calls, 3L)
  expect_equal(result$prediction, "finance")
})

test_that("generate: exact unlimited (max_calls=NULL)", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "Scientists discovered a new species in the Amazon."
  choices <- c("sports", "finance", "science", "politics")

  result <- generate(classifier, text = text, choices = choices, max_calls = NULL)

  assert_valid(result, choices, "adaptive_generate")
  expect_true(result$prediction %in% c("science", "politics"))
})

# ===========================================================================
# Batch variants
# ===========================================================================

test_that("batch_classify: 3 texts", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  texts <- c(
    "The goalkeeper made an incredible save!",
    "The central bank raised interest rates.",
    "The new smartphone features a revolutionary camera."
  )
  choices <- c("sports", "finance", "technology")
  expected <- c("sports", "finance", "technology")

  results <- batch_classify(classifier, texts = texts, choices = choices)

  expect_equal(length(results), length(texts))
  for (i in seq_along(texts)) {
    assert_valid(results[[i]], choices, "multi_call")
    expect_equal(results[[i]]$prediction, expected[i])
  }
})

test_that("batch_generate: 3 texts", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  texts <- c(
    "The team secured a decisive victory.",
    "Markets rallied on positive economic data.",
    "The software update fixes critical security vulnerabilities."
  )
  choices <- c("sports", "finance", "technology")
  expected <- c("sports", "finance", "technology")

  results <- batch_generate(classifier, texts = texts, choices = choices, max_calls = 1L)

  expect_equal(length(results), length(texts))
  for (i in seq_along(texts)) {
    assert_valid(results[[i]], choices, "adaptive_generate")
    expect_equal(results[[i]]$prediction, expected[i])
  }
})

# ===========================================================================
# Dataset evaluation -- classify + generate, save CSV
# ===========================================================================

test_that("dataset: classify and generate, save CSV", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  source("local_tests/dataset_runner.R")
  run_dataset_and_save_csv(
    classifier = classifier,
    backend_name = "ollama",
    llm_name = MODEL
  )
})
