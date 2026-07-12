# LOCAL-ONLY integration tests against a real SGLang server.
#
# This file lives under local_tests/ and is NOT part of R CMD check
# (excluded via .Rbuildignore). It exercises a running local SGLang instance
# and the Qwen2.5-3B-Instruct-GGUF model through both scoring methods of
# llm_classifier():
#
# * classify()  -- exact multi-call completion scoring (method="multi_call")
# * generate()  -- adaptive constrained generation (method="adaptive_generate")
#
# Prerequisites
# -------------
# 1. SGLang server running on port 30000 with the GGUF model:
#
#     docker compose up  # uses the sglang-qwen-gguf service
#
#    The server loads qwen2.5-3b-instruct-q4_k_m.gguf with
#    --load-format gguf and --tokenizer-path Qwen/Qwen2.5-3B-Instruct.
#
# 2. The model loaded and reachable at http://localhost:30000/v1
#
# Run with:
#
#     Rscript local_tests/test_local_sglang.R
#
# The whole script skips automatically if SGLang is unreachable or the model
# is not present, so sourcing it elsewhere never hard-fails.
#
# Note: SGLang's first request after a cold start can take ~15s while the model
# loads, so the skip guards use generous timeouts.

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

MODEL <- "Qwen2.5-3B-Instruct-GGUF"
HOST <- "localhost"
PORT <- 30000
BASE_URL <- paste0("http://", HOST, ":", PORT, "/v1")

# ---------------------------------------------------------------------------
# Skip guards: only run against a reachable server + present model
# ---------------------------------------------------------------------------

port_open <- function(host = "localhost", port, timeout = 2) {
  con <- tryCatch(
    socketConnection(host = host, port = port, timeout = timeout, open = "r"),
    error = function(e) NULL
  )
  if (is.null(con)) return(FALSE)
  close(con)
  TRUE
}

model_present <- function(host = HOST, port = PORT) {
  # SGLang reports the full filesystem path as the model ID (e.g. the GGUF
  # file path). Match by substring so the short MODEL display name used in
  # API requests doesn't need to match the path exactly.
  tryCatch({
    resp <- jsonlite::fromJSON(
      paste0("http://", host, ":", port, "/v1/models"),
      simplifyVector = FALSE
    )
    ids <- vapply(resp$data %||% list(), function(m) m$id %||% "", character(1))
    ids_lower <- tolower(ids)
    any(grepl("qwen2.5-3b-instruct", ids_lower, fixed = TRUE) &
        grepl("gguf", ids_lower, fixed = TRUE))
  }, error = function(e) FALSE)
}

skip_if_no_server <- function() {
  if (!port_open(host = HOST, port = PORT)) {
    skip(paste0("SGLang server not reachable at ", HOST, ":", PORT))
  }
}

skip_if_no_model <- function() {
  if (!model_present()) {
    skip(paste0("Model '", MODEL, "' not found on the SGLang server"))
  }
}

# Build the classifier
make_classifier <- function() {
  backend <- sglang_backend(model = MODEL, base_url = BASE_URL)
  llm_classifier(backend)
}

# ---------------------------------------------------------------------------
# Shared assertion helper
# ---------------------------------------------------------------------------

assert_valid <- function(result, choices, method) {
  expect_s3_class(result, "classification_result")
  expect_equal(result$method, method)
  expect_true(result$prediction %in% choices,
              info = paste0("prediction '", result$prediction, "' not in choices"))
  expect_true(result$confidence >= 0.0 && result$confidence <= 1.0)
  expect_setequal(names(result$probabilities), choices)
  expect_true(abs(sum(result$probabilities) - 1.0) < 1e-6)
}

# ===========================================================================
# classify() -- exact multi-call completion scoring (N calls for N labels)
# ===========================================================================

test_that("test_classify_basic: simple 4-way topic classification (multi-call)", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "The new quantum processor architecture drastically reduces latency."
  choices <- c("technology", "sports", "politics", "entertainment")

  result <- classify(classifier, text = text, choices = choices)

  cat("\n[classify] text=", deparse(text), "\n", sep = "")
  cat("  prediction=", result$prediction, "  confidence=", sprintf("%.2f%%", result$confidence * 100), "\n", sep = "")
  cat("  n_calls=", result$n_calls, "\n", sep = "")

  assert_valid(result, choices, "multi_call")
  expect_false(result$approximate)
  expect_equal(result$n_calls, length(choices))
  expect_equal(result$prediction, "technology")
})

test_that("test_classify_with_descriptions: named list choices with descriptions (multi-call)", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "This restaurant has amazing food but terrible service."
  choices <- list(
    positive = "Text expresses happiness, satisfaction, or approval",
    negative = "Text expresses anger, disappointment, or disapproval",
    mixed = "Text contains both positive and negative sentiments",
    neutral = "Text is factual without strong emotional content"
  )
  labels <- names(choices)

  result <- classify(classifier, text = text, choices = choices)

  cat("\n[classify+desc] text=", deparse(text), "\n", sep = "")
  cat("  prediction=", result$prediction, "  confidence=", sprintf("%.2f%%", result$confidence * 100), "\n", sep = "")

  assert_valid(result, labels, "multi_call")
  expect_true(result$prediction %in% c("negative", "mixed"))
})

test_that("test_classify_custom_prompt: custom system prompt for financial sentiment", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "The quarterly earnings exceeded analyst expectations."
  choices <- c("bullish", "bearish", "neutral")

  result <- classify(
    classifier,
    text = text,
    choices = choices,
    system_prompt = paste(
      "You are a financial sentiment analyzer.",
      "Classify financial news based on market sentiment."
    )
  )

  cat("\n[classify+prompt] text=", deparse(text), "\n", sep = "")
  cat("  prediction=", result$prediction, "  confidence=", sprintf("%.2f%%", result$confidence * 100), "\n", sep = "")

  assert_valid(result, choices, "multi_call")
  expect_equal(result$prediction, "bullish")
})

# ===========================================================================
# generate() -- adaptive constrained generation (1..max_calls calls)
# ===========================================================================

test_that("test_generate_single_call: max_calls=1 single constrained call", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "The team won the championship!"
  choices <- c("sports", "finance", "science", "politics")

  result <- generate(classifier, text = text, choices = choices, max_calls = 1L)

  cat("\n[generate max_calls=1] text=", deparse(text), "\n", sep = "")
  cat("  prediction=", result$prediction, "  confidence=", sprintf("%.2f%%", result$confidence * 100), "\n", sep = "")
  cat("  approximate=", result$approximate, "  n_calls=", result$n_calls, "\n", sep = "")

  assert_valid(result, choices, "adaptive_generate")
  expect_equal(result$n_calls, 1L)
  expect_equal(result$prediction, "sports")
})

test_that("test_generate_adaptive: max_calls=3 allow up to 3 calls", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "Stock prices plummeted after the announcement."
  choices <- c("sports", "finance", "science", "politics")

  result <- generate(classifier, text = text, choices = choices, max_calls = 3L)

  cat("\n[generate max_calls=3] text=", deparse(text), "\n", sep = "")
  cat("  prediction=", result$prediction, "  confidence=", sprintf("%.2f%%", result$confidence * 100), "\n", sep = "")
  cat("  approximate=", result$approximate, "  n_calls=", result$n_calls, "\n", sep = "")

  assert_valid(result, choices, "adaptive_generate")
  expect_true(result$n_calls >= 1 && result$n_calls <= 3)
  expect_equal(result$prediction, "finance")
})

test_that("test_generate_exact: max_calls=NULL fully recursive resolution", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  text <- "Scientists discovered a new species in the Amazon."
  choices <- c("sports", "finance", "science", "politics")

  result <- generate(classifier, text = text, choices = choices, max_calls = NULL)

  cat("\n[generate max_calls=NULL] text=", deparse(text), "\n", sep = "")
  cat("  prediction=", result$prediction, "  confidence=", sprintf("%.2f%%", result$confidence * 100), "\n", sep = "")
  cat("  approximate=", result$approximate, "  n_calls=", result$n_calls, "\n", sep = "")

  assert_valid(result, choices, "adaptive_generate")
  expect_true(result$prediction %in% c("science", "politics"))
})

# ===========================================================================
# Batch variants
# ===========================================================================

test_that("test_batch_classify: batch multi-call classification", {
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

  expect_length(results, length(texts))
  for (i in seq_along(texts)) {
    cat("\n[batch_classify] ", deparse(texts[i]), "\n", sep = "")
    cat("  -> ", results[[i]]$prediction, " (", sprintf("%.2f%%", results[[i]]$confidence * 100), ")\n", sep = "")
    assert_valid(results[[i]], choices, "multi_call")
    expect_equal(results[[i]]$prediction, expected[i])
  }
})

test_that("test_batch_generate: batch adaptive generation with max_calls=1", {
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

  expect_length(results, length(texts))
  for (i in seq_along(texts)) {
    cat("\n[batch_generate] ", deparse(texts[i]), "\n", sep = "")
    cat("  -> ", results[[i]]$prediction, " (", sprintf("%.2f%%", results[[i]]$confidence * 100), ")\n", sep = "")
    assert_valid(results[[i]], choices, "adaptive_generate")
    expect_equal(results[[i]]$prediction, expected[i])
  }
})

# ===========================================================================
# Dataset evaluation -- classify + generate on dataset_runner.R, save CSV
# ===========================================================================

test_that("test_dataset: run full dataset through classify() and generate(), save CSV", {
  skip_if_no_server()
  skip_if_no_model()
  classifier <- make_classifier()

  source("dataset_runner.R")
  run_dataset_and_save_csv(
    classifier = classifier,
    backend_name = "sglang",
    llm_name = MODEL
  )
})
