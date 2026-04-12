# 31 — Scaling Audit and Fixes

## Scope

Deep dive into every function exercised by the two new vignettes
(`deduplicate-50k.Rmd` and `transactions.Rmd`) to identify and fix
scaling issues.  Cross-referenced against splink's patterns in
`../splink`.  Prior first-pass findings documented in `deep-dive-notes.md`.

---

## Bugs Fixed

### 1. Integer overflow in pair counts

**Files:** `R/il_count_pairs.R`, `R/il_largest_blocks.R`, `R/utils-sql.R`

R integers overflow at 2^31 − 1 ≈ 2.1 billion.  For n = 50,000,
`n * (n - 1)` = 2,499,950,000 — exceeds 32-bit range and produces `NA`.
This propagated silently through all downstream arithmetic.

- `il_count_pairs.R`: Coerce `n_l` to `as.numeric()` before `n * (n-1)`
  arithmetic; replace all `as.integer()` wrapping pair counts with
  `as.numeric()`.
- `il_largest_blocks.R`: Same coercion for `n_records * (n_records - 1L)`.
- `utils-sql.R`: `count_blocked_pairs()` returns `as.numeric()` instead
  of `as.integer()`.
- `il_suggest_blocking.R` already had correct coercion.

### 2. NA guarding for prior (safe_prior)

**Files:** `R/utils-scoring.R`, and 7 call sites

R's `%||%` only catches `NULL`, not `NA`.  SQL NULLs arrive as `NA` in R,
and integer overflow produces `NA` — both bypass `%||%`.  Chain:
overflow → `NA` prior → `%||%` passes through → `log(NA)` →
`NaN` weights → garbage params.

Created `safe_prior()` helper in `utils-scoring.R` that guards both
`NULL` and `NA`, defaulting to 0.05.  Replaced all 7 call sites:

- `il_find_matches.R`
- `il_score_missing_edges.R`
- `il_waterfall.R`
- `predict.R`
- `utils-evaluation.R`
- `utils-sql.R`
- `il_estimate_em.R`

### 3. UNION ALL (matching splink)

**Files:** `R/utils-sql.R`, `R/utils-em.R`

Splink uses `UNION ALL` (not `UNION`) when combining blocking rules
(`blocking.py:681`).  `UNION` forces a DISTINCT over the entire result
which is redundant when an outer `GROUP BY` or explicit `DISTINCT` is
present.

- `build_gamma_query()`: `UNION` → `UNION ALL` between blocking-rule
  sub-queries.
- `get_blocked_pairs()`: `UNION` → `UNION ALL`.
- `get_all_pairs()`: `UNION` → `UNION ALL`.

### 4. Deferred DISTINCT (major performance win)

**Files:** `R/utils-sql.R`, `R/utils-em.R`

The previous approach wrapped all blocking-rule output in
`SELECT DISTINCT *` at the `build_gamma_query` level — forcing DuckDB to
deduplicate millions of rows including all gamma and TF columns.  Splink
skips this entirely.

Changed `build_gamma_query()` to accept a `deduplicate` parameter
(default `FALSE`).  Deduplication is now applied where it's cheapest:

| Caller | Dedup strategy |
|---|---|
| `get_pairs_with_gamma_counts()` (EM) | `GROUP BY` aggregation handles it |
| `get_pairs_with_gammas()` (predict, collect=TRUE) | `deduplicate = TRUE` |
| `build_scored_query()` (predict, collect=FALSE) | `SELECT DISTINCT` on scored output (after threshold filter — far fewer rows) |

For the 50k dedupe case, this removes a sort/hash over ~3M rows at the
gamma level and replaces it with a DISTINCT over ~112k scored rows.

### 5. Duplicate weight computation in evaluation

**File:** `R/utils-evaluation.R`

`score_labeled_pairs()` embedded `{weight_expr}` twice in a single SQL
statement — once for `match_weight` and once inside the logistic
transform for `match_probability`.  Each occurrence expanded to N CASE
expressions (one per comparison × gamma level).

Fixed with 3-level nesting: inner computes gammas, middle computes
`match_weight`, outer computes `match_probability` referencing the
computed alias.

### 6. Waterfall tf_adjs NA guard

**File:** `R/il_waterfall.R` (already in place)

Confirmed the guard `if (is.na(val)) 0 else val` is present for
TF adjustment columns that may be missing from predictions.

---

## Splink Comparison Findings

Cross-checked against `../splink` (Python splink codebase):

| Area | Splink approach | irelink status |
|---|---|---|
| Blocking rule combination | `UNION ALL`, no DISTINCT | ✅ Matched |
| Exploding rule dedup | `GROUP BY` on exploded output | ✅ Not applicable (no exploding rules yet) |
| Prior storage | `probability_two_random_records_match` | ✅ `model$params$prior` |
| Bayes factor formula | `prior/(1-prior)` × per-comparison BFs | ✅ `log(prior/(1-prior)) + weight * ln2` (equivalent) |
| Link-only pair generation | `l.source_dataset != r.source_dataset` | ✅ `build_table_pairs` uses separate table names |
| Link-only pair count | `count_l * count_r` (no /2) | ✅ `il_estimate_prior` line 82 |
| NULL handling in CASE | Implicit (NULLs fail condition) | ✅ `null_guard` clause in `sql_gamma_case` |
| SELECT DISTINCT in predict | Not used | ✅ Now deferred + minimal |

---

## Performance Results

Tested on Windows, DuckDB backend, after all fixes:

### 50k dedupe vignette

| Step | Time |
|---|---|
| `il_model` | 0.08s |
| `il_estimate_prior` | 0.05s |
| `il_estimate_u` (5M pairs) | 6.4s |
| `il_estimate_em` × 2 | 0.3s + 0.9s |
| `predict(lazy)` | 0.28s |
| `predict(collect)` | 0.67s |
| `il_accuracy` | 4.5s |
| **Max recall** | **1.0** |
| **Best F1** | **0.93** |

### Transactions linking vignette

| Step | Time |
|---|---|
| `il_model` | 0.11s |
| `il_estimate_u` (1M pairs) | 1.5s |
| `il_estimate_em` × 2 | 0.08s + 0.2s |
| `predict(collect, t=0.001)` | 1.1s |
| `il_accuracy` | 6.5s |
| **Max recall** | **1.0** |
| **Best F1** | **0.69** |

The recall issue from `deep-dive-notes.md` (recall ~0.35 at threshold 0)
is resolved.  Root causes were:

1. Integer overflow in prior → `NA` → broken scoring
2. `%||%` not catching `NA` from SQL NULLs
3. `UNION` deduplication removing valid blocking-rule output

---

## Files Modified

- `R/il_count_pairs.R` — integer overflow
- `R/il_largest_blocks.R` — integer overflow
- `R/utils-sql.R` — `count_blocked_pairs` overflow, `UNION ALL`,
  deferred DISTINCT, `safe_prior`
- `R/utils-scoring.R` — `safe_prior()` helper
- `R/utils-em.R` — `UNION ALL`, deduplicate param
- `R/utils-evaluation.R` — weight computation nesting
- `R/il_estimate_em.R` — `safe_prior`
- `R/il_find_matches.R` — `safe_prior`
- `R/il_score_missing_edges.R` — `safe_prior`
- `R/il_waterfall.R` — `safe_prior`
- `R/predict.R` — `safe_prior`

All 773 tests pass after changes (10 expected skips).
