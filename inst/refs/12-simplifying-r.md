# Stage 5 — Code Simplification Report

## Summary

Stage 5 audited the entire R codebase for duplicated logic and repeated
patterns, then extracted shared helpers into utility files.  Nine
distinct duplication categories were identified and resolved.  After all
changes, the full test suite (**334 / 334**) continues to pass with zero
failures and zero skips.

---

## Utility files created

| File | Helpers added | Purpose |
|------|---------------|---------|
| `R/utils-scoring.R` (new) | `extract_mu_vectors()`, `score_gamma_matrix()`, `weight_to_probability()`, `per_comparison_contribution()` | Scoring math shared by `predict.R`, `il_find_matches.R`, `il_waterfall.R` |
| `R/utils-evaluation.R` (new) | `canonical_pair_key()`, `score_labeled_pairs()` | Evaluation helpers shared by `il_accuracy.R`, `il_errors.R` |
| `R/utils-sql.R` (extended) | `build_select_aliases()`, `build_blocking_condition()`, `count_blocked_pairs()` | SQL generation shared by `utils-em.R`, `il_estimate_prior.R`, `il_count_pairs.R`, `il_deterministic_link.R` |
| `R/utils-classes.R` (extended) | `new_comparison_level()` | Single constructor for `il_comparison_level` S3 objects |

---

## Duplication categories resolved

### 1. Parameter extraction loop

**Before:** Identical 8-line `for` loop extracting `m_match`, `m_nonmatch`,
`u_match`, `u_nonmatch` from the parameters tibble appeared in
`predict.R`, `il_find_matches.R`, and `il_waterfall.R`.

**After:** Single call to `extract_mu_vectors(params, comp_names)`.

### 2. Gamma scoring loop

**Before:** Identical loop computing `match_weight` by iterating over
comparisons, selecting log2 ratios based on gamma values, appeared in
`predict.R` and `il_find_matches.R`.

**After:** Single call to `score_gamma_matrix(gamma_mat, mu)`.

### 3. Log-odds to probability conversion

**Before:** Two-line formula (`log_odds <- ...; 1 / (1 + exp(...))`)
duplicated in `predict.R` and `il_find_matches.R`.

**After:** Single call to `weight_to_probability(match_weight, prior)`.

### 4. Per-comparison contribution (waterfall)

**Before:** `il_waterfall.R` had its own 12-line loop extracting m/u
parameters and computing per-comparison weights, duplicating the core
logic from `predict.R`.

**After:** Reuses `extract_mu_vectors()` + `per_comparison_contribution()`.

### 5. Canonical pair key construction

**Before:** Identical `pair_key_fn` lambda defined locally in both
`il_accuracy.R` and `il_errors.R`.

**After:** Shared `canonical_pair_key(id_l, id_r)` in `utils-evaluation.R`.

### 6. Predict-and-lookup for labeled pairs

**Before:** Both `il_accuracy.R` and `il_errors.R` called `predict()` at
threshold 0, built key→probability maps, then looked up each labeled
pair. ~15 duplicated lines each.

**After:** Single call to `score_labeled_pairs(model, labels)` returns
`label_probs`, `label_weights`, and `actual_positive`.

### 7. SQL SELECT alias construction

**Before:** `paste(sprintf("l.%s AS l_%s", cols, cols), collapse = ", ")`
appeared three times: twice in `utils-em.R` (`get_blocked_pairs` and
`get_all_pairs`) and once in `il_deterministic_link.R`.

**After:** `build_select_aliases(cols)` returns a list with `$left` and
`$right` SQL fragments.

### 8. Blocking WHERE clause construction

**Before:** `vapply(cols, function(col) sprintf("l.%s = r.%s", ...), ...)` +
`paste(..., collapse = " AND ")` appeared four times across `utils-em.R`,
`il_estimate_prior.R`, `il_count_pairs.R`, and `il_deterministic_link.R`.

**After:** `build_blocking_condition(columns)` returns the complete WHERE
fragment.

### 9. Comparison level constructor boilerplate

**Before:** Every `cl_*()` function repeated the same
`structure(list(method = ..., is_null_level = FALSE, is_else_level = FALSE), class = "il_comparison_level")`
pattern — 16 instances across 10 files.

**After:** All use `new_comparison_level(method, ...)` from
`utils-classes.R`.

---

## Files modified

### Callers updated to use `utils-scoring.R`

| File | Change |
|------|--------|
| `R/predict.R` | Replaced ~20-line param extraction + scoring block with 3 function calls |
| `R/il_find_matches.R` | Same pattern; also removed redundant variable declarations |
| `R/il_waterfall.R` | Replaced 12-line contribution loop with `extract_mu_vectors()` + `per_comparison_contribution()` |

### Callers updated to use `utils-evaluation.R`

| File | Change |
|------|--------|
| `R/il_accuracy.R` | Replaced 15-line predict+lookup with `score_labeled_pairs()` |
| `R/il_errors.R` | Same; also simplified weight lookup |

### Callers updated to use `utils-sql.R` helpers

| File | Change |
|------|--------|
| `R/utils-em.R` | `get_blocked_pairs()` and `get_all_pairs()` use `build_select_aliases()` and `build_blocking_condition()` |
| `R/il_estimate_prior.R` | Blocking loop uses `build_blocking_condition()` + `count_blocked_pairs()` |
| `R/il_count_pairs.R` | Blocking loop uses `build_blocking_condition()` + `count_blocked_pairs()` |
| `R/il_deterministic_link.R` | Uses `build_select_aliases()` and `build_blocking_condition()` |

### Callers updated to use `new_comparison_level()`

| File | Functions |
|------|-----------|
| `R/cl_exact.R` | `cl_exact()` |
| `R/cl_custom.R` | `cl_custom()` |
| `R/cl_jaro_winkler.R` | `cl_jaro_winkler()`, `cl_jaro()` |
| `R/cl_levenshtein.R` | `cl_levenshtein()`, `cl_damerau_levenshtein()` |
| `R/cl_jaccard.R` | `cl_jaccard()` |
| `R/cl_cosine.R` | `cl_cosine()` |
| `R/cl_array_intersect.R` | `cl_array_intersect()` |
| `R/cl_numeric_diff.R` | `cl_numeric_diff()`, `cl_pct_diff()` |
| `R/cl_distance_km.R` | `cl_distance_km()` |
| `R/cl_date_diff.R` | `cl_date_diff()` |
| `R/cl_levels.R` | `cl_levels()`, `cl_null()`, `cl_else()`, `cl_and()`, `cl_or()`, `cl_not()` |

---

## Lines of code impact

Approximate net reduction in duplicated logic:

- **~40 lines** removed from scoring callers (predict, find_matches, waterfall)
- **~30 lines** removed from evaluation callers (accuracy, errors)
- **~35 lines** removed from SQL callers (utils-em, estimate_prior, count_pairs, deterministic_link)
- **~50 lines** removed from cl_* constructor boilerplate
- **~80 lines** added across the four utility files

Net change: roughly **75 fewer lines** of duplicated code, with the
remaining logic centralised in well-documented, testable helpers.

---

## Verification

All 334 tests pass after every refactoring batch:

```
Duration: 55.7 s
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 334 ]
```

No behavioural changes were introduced. The refactoring is purely
structural — every helper reproduces the exact same computation as the
code it replaced.
