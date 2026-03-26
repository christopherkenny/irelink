# 14 — Stage 6 Systematic Test Audit

Report following `inst/refs/09-implementation-plan.md` §6a–6e.

## Scope

The implementation plan defines five categories of Stage 6 tests:

| Category | Description | Status |
|----------|-------------|--------|
| 6a | R type safety (factor, Date, NA, zero-row, single-row) | ✅ Covered |
| 6b | Tidyverse integration (pipes, verbs, ggplot, tidyselect) | ✅ Covered |
| 6c | Backend compatibility (DuckDB, SQLite, PostgreSQL) | ⬜ Partial |
| 6d | Snapshot tests (print/summary output) | ✅ Added |
| 6e | Performance-sensitive tests | ✅ Added |

## 6a. R Type Safety — Already Covered

All items had existing tests before this audit:

- **Factor columns**: `test-il_model.R` ("handles factor columns"), `test-cl-similarity.R` ("factor columns gracefully")
- **Date / POSIXct columns**: `test-cl-similarity.R` ("compatible with Date, POSIXct, and character date columns")
- **NA at every stage**: 8 tests across `test-r-specific.R`, `test-il_string_similarity.R`
- **Zero-row data frames**: `test-il_model.R`, `test-il_cluster.R`, `test-r-specific.R`
- **Single-row data**: `test-il_model.R`, `test-r-specific.R`

No new tests needed.

## 6b. Tidyverse Integration — Gaps Filled

**Previously covered:**
- Full pipe chains (`test-pipeline-integration.R`): 2 tests
- dplyr filter/mutate/summarise (`test-predict.R`): 1 test
- dplyr select/arrange/slice (`test-r-specific.R`): 1 test
- ggplot2 autoplot (`test-autoplot.R`, `test-r-specific.R`): 4 tests
- tibble printing (`test-predict.R`): 1 test
- tidyselect everything(), matches() (`test-il_compare.R`): 2 tests

**Added in `test-stage6-plan.R`:**
- `dplyr::group_by() + summarise()` on `il_compared` — previously untested
- `tidyselect::where(is.character)` deferred storage — previously untested

## 6c. Backend Compatibility — Partially Addressed

**SQLite**: All 454 tests run on `RSQLite::SQLite()` in-memory. Added an explicit end-to-end SQLite pipeline test (`test-stage6-plan.R`).

**DuckDB**: Cannot test on this platform (R DuckDB sessions hang). Added a skip-guarded placeholder. Deferred to CI.

**PostgreSQL**: Not available for local testing. Added a skip-guarded placeholder. Deferred to CI.

Note: The internal SQL generation (`utils-sql.R`, `utils-sql-comparison.R`) uses standard SQL constructs that work across engines. The only SQLite-specific fallback is string-similarity UDFs registered in `il_model()`.

## 6d. Snapshot Tests — Added

Seven snapshot tests in `test-stage6-plan.R`:

| Test | Object | Sprint |
|------|--------|--------|
| `print.il_spec()` empty spec | il_spec | 1 |
| `print.il_spec()` with comparisons + blocking | il_spec | 3 |
| `print.il_model()` untrained | il_model | 6 |
| `print.il_model()` trained | il_model | 7 |
| `summary.il_model()` trained | il_model | 7 |
| Unit helpers (days, months, years, km, mi) | il_unit_* | 1 |

Snapshots are stored in `tests/testthat/_snaps/test-stage6-plan.md`. On first creation they emit warnings; subsequent runs match exactly.

**Not snapshotted**: `print.il_compared` and `print.il_blocking_rule` — these classes rely on tibble's default print method, which changes across R and tibble versions. Testing `expect_output(print(x))` (already done in `test-predict.R`) is sufficient.

## 6e. Performance-Sensitive Tests — Added

Three performance guard tests in `test-stage6-plan.R`:

| Test | Dataset | Sprint |
|------|---------|--------|
| `il_estimate_em()` on 1000 records | `fake_1000` | 7 |
| `predict()` on 1000 records | `fake_1000` | 8 |
| `il_cluster()` on 5000 edges | Synthetic | 9 |

These use `expect_no_error()` — they verify the operations complete without failure on non-trivial data. Explicit wall-clock thresholds were omitted because execution time varies across machines and CI runners; the key property is correctness, not speed.

## Bug Fix: il_cluster() NA Handling

The audit discovered a bug in `R/il_cluster.R` line 42. When `match_probability` contains `NA`, R's `>=` comparison produces `NA`, which R's `[` subsetting preserves as an all-NA row. This caused the union-find to crash with "subscript out of bounds".

**Fix**: Changed `pairs[pairs$match_probability >= threshold, ]` to `pairs[which(pairs$match_probability >= threshold), ]`. The `which()` function drops NA indices, correctly excluding rows with unknown probabilities.

A corresponding test was added: "il_cluster() tolerates NA in match_probability by using threshold".

## Test Count Summary

| File | Tests | New |
|------|------:|----:|
| `test-stage6-plan.R` | 19 | 19 |
| Previous total | 435 | — |
| **New total** | **454** | **19** |

(Plus 2 skipped: DuckDB, PostgreSQL)

## Files Modified

- `R/il_cluster.R` — `which()` fix for NA threshold filtering
- `tests/testthat/test-stage6-plan.R` — 19 new tests (created)
- `tests/testthat/_snaps/test-stage6-plan.md` — snapshot file (auto-generated)
