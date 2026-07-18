# Bug Report & Fix: `generate(max_calls)` Accuracy Regression in rollama v0.5.0

> This document mirrors the equivalent bug report from
> [ollama-classifier v0.6.0](https://github.com/paluigi/ollama-classifier/blob/v0.6.0/BUG_REPORT.md).
> rollama reproduces the same conceptual flaw (inherited from the v0.5.0
> port of the Python library) and applies the same fix.

## Executive Summary

The `generate()` method had a **conceptual flaw** in its adaptive cluster-resolution
algorithm. When `max_calls > 1`, supplementary API calls constrained the model to a
**subset** of labels, placing their logprobs in a **different probability space** than
the initial full-label call. These incompatible logprobs were mixed into a single
geometric mean, producing invalid scores that **monotonically decreased** accuracy as
`max_calls` grew — confirmed experimentally in the Python reference implementation
across all 4 choice-configurations and 4 call budgets (16 variations, 637 products
each).

**Root cause**: Mixing logprobs from different constraint contexts.
**Fix**: **Reproportioning** — supplementary calls only redistribute probability mass
*within* a cluster, never changing between-group totals.

---

## 1. Experimental Confirmation

The experiment (`summary.txt`, ollama-classifier v0.5.0, qwen2.5:3b-instruct)
runs `generate()` at `max_calls ∈ {1, 3, 5, 8}` across 4 choice-configurations.

### Accuracy — monotonic decrease in ALL configurations (before fix)

| Config | mc=1 | mc=3 | mc=5 | mc=8 | Δ (1→8) |
|---|---|---|---|---|---|
| names only | **73.8%** | 62.8% | 56.2% | 50.9% | −22.9 pp |
| names + opt-out | **70.6%** | 61.9% | 52.7% | 44.3% | −26.3 pp |
| names + descriptions | **72.8%** | 65.0% | 61.7% | 61.4% | −11.4 pp |
| desc. + opt-out | **67.8%** | 61.5% | 59.5% | 57.5% | −10.3 pp |

**Every configuration shows a monotonic accuracy decrease.**

### Reference: `classify()` (unaffected)

| Config | Accuracy |
|---|---|
| names only | 75.5% |
| names + opt-out | 74.7% |
| names + descriptions | 74.4% |
| desc. + opt-out | 71.3% |

---

## 2. Root Cause

### The Problematic Code Path

The original `generate()` used a BFS loop to resolve clusters:

```r
frontier <- list(list(labels = labels, resolved_length = 0L))
while (length(frontier) > 0 && (is.null(max_calls) || calls_made < max_calls)) {
  cluster <- frontier[[1]]
  cluster_labels <- cluster$labels  # SUBSET of all labels!

  response <- backend$chat(
    constrain_labels = cluster_labels,  # ← Different constraint set!
    ...
  )
  # Logprobs from this call were APPENDED into accumulated scores
  # and fed into a single geometric mean
}
```

### Why It Breaks

When the constraint set changes from `{A, B, C}` → `{A, B}` → `{B}`, the logprob
distribution changes fundamentally:

| Call | Constraint | Logprob behavior |
|---|---|---|
| Call 1 | `{A, B, C}` | Genuine 3-way competition (pre-mask) |
| Call 2 | `{A, B}` | C's probability mass redistributed to A and B |
| Call 3 | `{B}` | **Post-mask: forced token P≈1.0, logprob≈0.0** |

Post-mask logprobs (≈0.0) dilute the negative signal from genuine tokens in the
geometric mean, artificially inflating scores of labels with many unscored tokens.

### Concrete Mechanism

Labels: `A=[shared, a_end]` (2 tok), `B=[shared, b_mid, b1, b2, b3]` (5 tok)
Model's true preference: **A > B > C**

- **mc=1**: B = `geom_mean([-0.3, -0.6])` = **-0.45** → A wins ✓
- **mc=2**: B = `geom_mean([-0.3, -0.6, 0.0, 0.0, 0.0])` = **-0.18** (inflated!) → B wins ✗

---

## 3. The Fix: Hierarchical Reproportioning

### Approach

Keep `max_calls` as the sole parameter (`max_calls = 1` means no resolution).

**Call 1** constrains the model to all labels and produces an initial probability
distribution using divergence-aware logprobs. All logprobs come from the same
constraint context, so the distribution is internally consistent.

**Calls 2…max_calls** resolve *clusters*: groups of ≥2 non-winning labels that share a
scored prefix but diverge from the winner. For each cluster:

1. Make a constrained call over only the cluster's labels
2. Compute divergence-based relative weights (softmax of geometric-mean scores)
3. **Reproportion**: redistribute the cluster's total probability mass (summed from
   the initial distribution) according to these relative weights

```
P(group) from first call                # between groups, locked
relative_weight(L) from subset softmax  # within group
P_new(L) = P(group) × relative_weight(L) # hierarchical composition
```

Between-group probabilities are **never changed**. The subset call's absolute
logprobs may be shifted (post-mask), but only their **ratios** matter for
reproportioning — and ratios are preserved through renormalization.

### Key Properties (verified with mock backend)

1. **Accuracy never degrades** with increasing `max_calls`
2. **Between-group probability mass preserved** — B+C mass stays constant
3. **Within-group probabilities reproportioned** — B and C shift relative to each other
4. **Non-cluster labels unchanged** — P(A) remains fixed
5. **Probabilities always sum to 1.0**

### Verification Output

Reproduced in R via `tests/testthat/test-classifier.R` against a `MockBackend`:

```
max_calls  P(A)     P(B)     P(C)     pred  n_calls  P(B)+P(C)
1          0.4150   0.2925   0.2925   A     1        0.5850
2          0.4150   0.3071   0.2779   A     2        0.5850   preserved ✓
NULL       0.4150   0.3071   0.2779   A     2        0.5850   preserved ✓
```

### Changes (`R/classifier.R`)

`generate_fn()`:
1. Single constrained call over ALL labels → initial probabilities
2. `identify_unresolved_clusters()` finds multi-label clusters with shared prefixes
3. For each cluster (≥2 labels): subset call → relative weights → reproportion
4. Single-label clusters are skipped (nothing to reproportion)
5. Recursive: sub-clusters from each resolution are added to the frontier

The accumulated per-label logprobs for a cluster member are **replaced** (not
appended) by the subset call's logprobs, and only used to compute the
within-cluster relative weights.

### Tests

All 54 tests pass (40 new classifier tests + 14 existing backend tests),
including 3 regression tests ported from `ollama-classifier` v0.6.0
`TestMaxCallsMonotonicity`:

- `max_calls does not flip a correct prediction`: prediction stays correct for all `max_calls`
- `reproportion preserves between-group mass`: A's probability does not decrease with `max_calls`
- `single-token labels need no resolution calls`: single-token labels make exactly 1 call
