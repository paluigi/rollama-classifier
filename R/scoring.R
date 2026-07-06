#' Scoring utilities for classification
#'
#' Probability and scoring functions used by the adaptive `generate()` and
#' multi-call `classify()` methods. All length normalization uses geometric
#' mean, applied consistently across both methods.
#'
#' @name scoring
#' @keywords internal
NULL


#' Geometric-mean (length-normalized) log probability
#'
#' Computes the per-token average of log probabilities, equivalent to the log
#' of the geometric mean of token probabilities. Eliminates the length bias
#' that occurs when summing raw logprobs over labels with different token
#' counts.
#'
#' @param logprobs Numeric vector of per-token log probabilities.
#'
#' @return Numeric. Average per-token log probability.
#'
#' @keywords internal
geometric_mean_logprob <- function(logprobs) {
  if (length(logprobs) == 0) {
    stop("Cannot compute geometric mean of empty vector.", call. = FALSE)
  }
  valid <- logprobs[logprobs > -Inf]
  if (length(valid) == 0) return(-Inf)
  sum(valid) / length(valid)
}


#' Numerically stable softmax
#'
#' Computes softmax over a named numeric vector of log probabilities.
#'
#' @param logprobs Named numeric vector of log probabilities.
#'
#' @return Named numeric vector of probabilities summing to 1.
#'
#' @keywords internal
stable_softmax <- function(logprobs) {
  if (length(logprobs) == 0) {
    stop("Cannot compute softmax of empty vector.", call. = FALSE)
  }

  valid <- logprobs[logprobs > -Inf]

  if (length(valid) == 0) {
    n <- length(logprobs)
    probs <- rep(1 / n, n)
    names(probs) <- names(logprobs)
    return(probs)
  }

  max_lp <- max(valid)
  exp_vals <- ifelse(logprobs > -Inf, exp(logprobs - max_lp), 0)
  total <- sum(exp_vals)

  if (total == 0) {
    n <- length(logprobs)
    probs <- rep(1 / n, n)
    names(probs) <- names(logprobs)
    return(probs)
  }

  probs <- exp_vals / total
  names(probs) <- names(logprobs)
  probs
}


# =========================================================================
# Label prefix trie (nested list structure)
# =========================================================================

#' Create an empty label trie
#'
#' The trie is a nested list structure used by `generate()` to:
#' 1. Determine the minimum `top_logprobs` K (max branching factor).
#' 2. Find divergence points between the winning path and each label.
#' 3. Identify unresolved clusters for recursive resolution.
#'
#' @return A list representing an empty trie.
#' @keywords internal
label_trie <- function() {
  list(
    root = list(children = list(), is_terminal = FALSE, label = NULL),
    token_sequences = list()
  )
}

#' Insert a label into the trie
#'
#' Uses a recursive approach to rebuild the nested list, since R lists are
#' copy-on-modify and in-place mutation of nested nodes does not work.
#'
#' @param trie A trie from [label_trie()].
#' @param label Character. The label name.
#' @param tokens Character vector of token strings.
#'
#' @return A modified copy of the trie.
#'
#' @keywords internal
trie_insert <- function(trie, label, tokens) {
  trie$token_sequences[[label]] <- tokens
  trie$root <- .trie_insert_node(trie$root, tokens, label)
  trie
}

.trie_insert_node <- function(node, tokens, label) {
  if (length(tokens) == 0) {
    node$is_terminal <- TRUE
    node$label <- label
    return(node)
  }

  token <- tokens[1]
  rest <- tokens[-1]

  if (is.null(node$children[[token]])) {
    node$children[[token]] <- list(
      children = list(), is_terminal = FALSE, label = NULL
    )
  }

  node$children[[token]] <- .trie_insert_node(node$children[[token]], rest, label)
  node
}

#' Get max branching factor of trie
#'
#' Returns the maximum number of children at any node. This is the minimum
#' `top_logprobs` K needed to capture all sibling alternatives.
#'
#' @param trie A trie from [label_trie()].
#'
#' @return Integer. Max children count at any node.
#'
#' @keywords internal
trie_max_branching <- function(trie) {
  .max_branching <- function(node) {
    n_children <- length(node$children)
    if (n_children == 0) return(0L)
    child_max <- max(purrr::map_int(node$children, .max_branching))
    max(n_children, child_max)
  }
  .max_branching(trie$root)
}


# =========================================================================
# Divergence-aware scoring
# =========================================================================

#' Find divergence point between two token sequences
#'
#' Returns the 1-based index of the first position where the two sequences
#' differ. If they are identical up to the minimum length, returns
#' `min_len + 1` (meaning "no divergence within the overlapping range").
#'
#' @param label_tokens Character vector.
#' @param winning_tokens Character vector.
#'
#' @return Integer. First 1-based index where they differ, or `min_len + 1`.
#'
#' @keywords internal
divergence_point <- function(label_tokens, winning_tokens) {
  min_len <- min(length(label_tokens), length(winning_tokens))
  for (i in seq_len(min_len)) {
    if (label_tokens[i] != winning_tokens[i]) return(i)
  }
  min_len + 1L
}


#' Score labels from winning path (divergence-aware)
#'
#' For each label, computes the geometric-mean logprob over tokens up to the
#' divergence point from the winning path. Tokens at those positions are exact
#' because the conditioning prefix matches for both the label and the winner
#' up to that point.
#'
#' @param token_sequences Named list of `{label: [tokens]}`.
#' @param winning_label Character. The label that the model actually generated.
#' @param step_logprobs List of named numeric vectors. `step_logprobs[[i]]` is
#'   a named numeric vector `{token: logprob}` for position i.
#'
#' @return Named numeric vector of geometric-mean logprobs.
#'
#' @keywords internal
score_labels_from_winning_path <- function(token_sequences, winning_label,
                                            step_logprobs) {
  winning_tokens <- token_sequences[[winning_label]]
  labels <- names(token_sequences)
  scores <- numeric(length(labels))
  names(scores) <- labels

  for (label in labels) {
    label_tokens <- token_sequences[[label]]
    d <- divergence_point(label_tokens, winning_tokens)
    # Score tokens at positions 1..d (R is 1-based)
    n_scoring <- min(d, length(label_tokens), length(step_logprobs))

    if (n_scoring == 0) {
      scores[[label]] <- -Inf
      next
    }

    token_lps <- numeric(0)
    for (i in seq_len(n_scoring)) {
      token <- label_tokens[i]
      if (i <= length(step_logprobs) && token %in% names(step_logprobs[[i]])) {
        token_lps <- c(token_lps, step_logprobs[[i]][[token]])
      } else {
        token_lps <- c(token_lps, -Inf)
      }
    }

    scores[[label]] <- geometric_mean_logprob(token_lps)
  }

  scores
}


#' Get scored lengths per label
#'
#' Returns the number of tokens scored per label based on the divergence point.
#'
#' @param token_sequences Named list.
#' @param winning_label Character.
#'
#' @return Named integer vector.
#'
#' @keywords internal
get_scored_lengths <- function(token_sequences, winning_label) {
  winning_tokens <- token_sequences[[winning_label]]
  labels <- names(token_sequences)
  lengths <- integer(length(labels))
  names(lengths) <- labels

  for (label in labels) {
    label_tokens <- token_sequences[[label]]
    d <- divergence_point(label_tokens, winning_tokens)
    lengths[[label]] <- min(d, length(label_tokens))
  }

  lengths
}


#' Identify unresolved clusters
#'
#' Groups labels that are not fully resolved (scored_length < full length) and
#' share a common prefix at the already-scored positions.
#'
#' @param token_sequences Named list of `{label: [tokens]}`.
#' @param scored_lengths Named integer vector.
#'
#' @return A list of cluster lists, each with `labels` (character vector) and
#'   `resolved_length` (integer).
#'
#' @keywords internal
identify_unresolved_clusters <- function(token_sequences, scored_lengths) {
  # Filter to unresolved labels
  unresolved_labels <- character(0)
  for (label in names(token_sequences)) {
    if (scored_lengths[[label]] < length(token_sequences[[label]])) {
      unresolved_labels <- c(unresolved_labels, label)
    }
  }

  if (length(unresolved_labels) == 0) return(list())

  # Group by prefix at the already-scored length
  clusters <- list()
  for (label in unresolved_labels) {
    seq <- token_sequences[[label]]
    resolved <- scored_lengths[[label]]
    if (resolved > 0) {
      prefix <- paste(seq[seq_len(resolved)], collapse = "\u0001")
    } else {
      prefix <- ""
    }
    if (is.null(clusters[[prefix]])) {
      clusters[[prefix]] <- list(labels = label, resolved_length = resolved)
    } else {
      clusters[[prefix]]$labels <- c(clusters[[prefix]]$labels, label)
    }
  }

  purrr::map(clusters, ~ list(labels = .x$labels, resolved_length = .x$resolved_length))
}
