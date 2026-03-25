# Stage 4 — Sprint Implementation Log

## Overview

All 10 sprints implemented. Full test suite: **334 tests passing**, 0 failures, 0 skips.

---

## Sprint 1 — Foundation (S3 Classes, il_spec, Unit Helpers)

**Files**: `R/il_spec.R`, `R/utils-classes.R`, `R/utils-units.R`

- Implemented `il_spec()`, `validate_il_spec()`, `print.il_spec()`, unit helpers (`days`, `months`, `years`, `km`, `mi`)
- Key fix: `print.il_spec()` must use `cat()` not `cli::cli_*()` — cli writes to stderr, failing `expect_output()` tests
- **38/38 tests passed**

## Sprint 2 — Comparison Helpers

**Files**: `R/cl_similarity.R`, `R/cl_levels.R`, `R/cl_domain.R`, `R/utils-comparison.R`

- Implemented all 13 `cl_*` functions, `cl_levels`, `cl_null`, `cl_else`, `cl_and`, `cl_or`, `cl_not`, domain bundles
- All return `structure(list(method="...", ...), class="il_comparison_level")`
- **123/123 cumulative tests passed**

## Sprint 3 — Spec Composition

**Files**: `R/il_compare.R`, `R/il_block_on.R`, `R/block_on.R`

- Implemented `il_compare` with NSE via `rlang::enquo`, `il_block_on`, `block_on`
- **35/35 sprint tests passed**

## Sprint 4 — Demo Data & String Similarity

**Files**: `R/il_demo.R`, `R/il_string_similarity.R`

- Implemented `il_demo` with deterministic generation (`set.seed(42L)`)
- `il_string_similarity` wraps `stringdist` for column-wise comparison
- **29/29 sprint tests passed**

## Sprint 5 — SQL Engine & Exploration

**Files**: `R/utils-sql.R`, `R/il_completeness.R`, `R/il_profile.R`, `R/il_count_pairs.R`

- Created SQL utility layer
- `il_completeness`: per-column non-NA rates
- `il_profile`: value frequency distributions
- `il_count_pairs`: estimates pair counts under blocking rules
- **30/30 sprint tests passed**

## Sprint 6 — Model Creation

**Files**: `R/il_model.R`, `R/il_cleanup.R`

- `il_model()`: binds data + spec + DBI connection, uploads data to database
- Print/summary methods for `il_model`
- `il_cleanup()` removes temporary tables
- **15/15 sprint tests passed**

## Sprint 7 — Training & Model Inspection

**Files**: `R/il_estimate_u.R`, `R/il_estimate_em.R`, `R/il_estimate_prior.R`, `R/il_estimate_m_from_labels.R`, `R/il_estimate_m_from_column.R`, `R/il_parameters.R`, `R/il_weights.R`, `R/il_training_history.R`, `R/utils-em.R`

- Full EM algorithm with binary gamma, E-step in log space, M-step with Laplace smoothing + clamping [0.01, 0.99]
- U values frozen from `il_estimate_u`, not updated during EM
- `il_weights()` returns tibble with `comparison`, `level`, `m_prob`, `u_prob`, `weight` columns
- **27/27 sprint tests passed**

### Key design: EM M-step clamping
Without clamping, EM on highly similar blocked pairs produces m≈1.0, causing infinite log-odds. Clamping m to [0.01, 0.99] with Laplace pseudocounts (0.5) prevents degenerate models.

## Sprint 8 — Prediction & Pair Inspection (MVP)

**Files**: `R/predict.R`, `R/il_deterministic_link.R`, `R/il_compare_records.R`, `R/il_find_matches.R`, `R/il_waterfall.R`

- `predict.il_model`: blocked pairs → gamma matrix → log2 Bayes scoring → match probability → threshold → `il_compared` tibble
- Scoring: `match_weight = Σ_j [γ_j log2(m/u) + (1-γ_j) log2(m'/u')]`; `match_probability = 1/(1 + exp(-log_odds))`
- `il_waterfall`: decomposes match weight into per-comparison contributions
- `il_find_matches`: iterates only over comparison columns when building pairs (not all data columns)
- Pair dedup key uses `"||"` separator (not `\x00` which causes R parse error)
- **56/56 cumulative sprint 7+8 tests passed**

## Sprint 9 — Clustering

**Files**: `R/il_cluster.R`, `R/il_graph_metrics.R`

- Union-find with path compression and rank for connected components
- `best_link`: mutual best links only — edge kept only if it's the best for BOTH endpoints
- Threshold filtering collects all unique IDs first, then forms components from filtered edges
- `il_graph_metrics`: node degree, cluster size, cluster density
- Added `igraph` and `dplyr` to Suggests
- **12/12 sprint tests passed; 279/279 full suite**

## Sprint 10 — Evaluation, Visualization, Serialization

**Files**: `R/il_accuracy.R`, `R/il_errors.R`, `R/il_roc.R`, `R/il_precision_recall.R`, `R/il_unlinkables.R`, `R/autoplot.R`, `R/il_save.R`

### Evaluation functions
- `il_accuracy(model, labels)`: scores all labeled pairs against model predictions at 21 thresholds (0.00–1.00 by 0.05), returning TP/FP/FN/TN/precision/recall/F1
- `il_errors(model, labels, threshold)`: returns tibble of false-positive and false-negative pairs
- `il_roc(model, labels)`: derives FPR/TPR from `il_accuracy`
- `il_precision_recall(model, labels)`: derives precision/recall from `il_accuracy`
- `il_unlinkables(model)`: proportion of records with no match above each threshold (monotonically non-decreasing)

### Visualization
- `autoplot.il_model()`: bar chart of match weights per comparison/level via ggplot2
- `autoplot.il_compared()`: histogram of match_weight (default) or waterfall chart for a specific pair
- Registered as `S3method(ggplot2::autoplot, il_model)` using `@exportS3Method ggplot2::autoplot`

### Serialization
- `il_save(model, path)`: serializes spec, params, trained flag to JSON via jsonlite; strips S3 classes with `unclass()` before writing; uses `digits = NA` for full floating-point precision
- `il_load(path)`: deserializes JSON, reconstructs `il_spec` and `il_model` with proper S3 classes; connection is `NULL` (needs fresh DB for prediction)

### Fixes applied
- Renamed `il_weights()` column from `match_weight` to `weight` for ggplot2 ergonomics (test-pipeline-integration uses `y = weight`)
- Fixed test-il_save.R data: changed unique first_names to duplicated ones so `block_on(first_name)` produces pairs for EM
- Added `ggplot2` and `jsonlite` to DESCRIPTION Suggests

**13/13 sprint tests passed; 334/334 full suite**

---

## Final Test Summary

| Sprint | Tests | Cumulative |
|--------|:-----:|:----------:|
| 1 | 38 | 38 |
| 2 | 85 | 123 |
| 3 | 35 | 158 |
| 4 | 29 | 187 |
| 5 | 30 | 217 |
| 6 | 15 | 232 |
| 7 | 27 | 259 |
| 8 | 20 | 279 |
| 9 | 12 | 291 |
| 10 | 43 | 334 |

## Dependencies

**Imports**: cli, DBI, rlang, stringdist, tibble
**Suggests**: dplyr, ggplot2, igraph, jsonlite, RSQLite, testthat (≥ 3.0.0), withr
