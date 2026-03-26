# R-Specific Test Additions

## Summary

The original 334 tests were primarily translations of splink's Python
test suite, rewritten for irelink's pipe-friendly API. This audit
identified gaps specific to R idioms — NA/NULL handling, type coercion,
S3 dispatch, vectorization guards, error classes, edge-case boundaries,
and dplyr verb compatibility — and added **101 new tests** in
`tests/testthat/test-r-specific.R`.

Final count: **435 tests, 0 failures, 0 skips.**

---

## Methodology

1. Read `inst/refs/stage-03-notes.md` and the full test suite (28 files)
   to inventory what was already covered.
2. Read every exported R function to catalogue argument signatures,
   validation logic, return types, and S3 methods.
3. Compared the two lists against R-specific concerns that Python tests
   would never cover (NA propagation, factor coercion, Inf/NaN guards,
   S3 print contracts, tibble subclass inheritance, dplyr verb compat).
4. Wrote targeted tests for each gap, organised by sprint.
5. Fixed one real bug found during the audit (see below).

---

## Bug found and fixed

**`check_unit_input()` accepted `Inf` and `NaN`.**  The validator in
`R/utils-unit-helpers.R` checked `is.na(n)` but not `is.infinite(n)` or
`is.nan(n)`, so `days(Inf)` silently created a tagged value. Added
`is.infinite(n) || is.nan(n)` to the guard clause.

---

## Tests added by category

### 1. Unit helper edge cases (Sprint 1) — 8 tests

| Test | What it verifies |
|------|-----------------|
| `unit helpers reject NA input` | `days(NA)`, `km(NA_integer_)`, etc. all error |
| `unit helpers accept zero` | `days(0)` and `km(0)` are valid |
| `unit helpers reject length > 1 input` | `days(c(1,2))` errors |
| `unit helpers reject Inf and NaN` | `days(Inf)`, `km(NaN)` error (new bug fix) |

### 2. S3 class consistency (Sprint 1) — 4 tests

| Test | What it verifies |
|------|-----------------|
| `il_spec inherits from list` | Spec is both `il_spec` and `list` |
| `il_compared inherits from tbl_df` | Compared is `il_compared`, `tbl_df`, `data.frame` |

### 3. Comparison level validation (Sprint 2) — 8 tests

| Test | What it verifies |
|------|-----------------|
| `similarity thresholds reject NA` | `cl_jaro_winkler(NA)` errors |
| `distance thresholds reject NA` | `cl_levenshtein(NA)` errors |
| `similarity thresholds reject Inf` | `cl_jaro_winkler(Inf)` errors |
| `cl_custom() rejects non-character` | Numeric, NULL, vector inputs error |
| `cl_levels() rejects non-level args` | Strings and numbers error |

### 4. Tidyselect and pipe chaining (Sprint 3) — 4 tests

| Test | What it verifies |
|------|-----------------|
| `il_compare() with c() accumulates` | `c(first_name, surname)` → 2 entries |
| `piping preserves both comparisons and blocks` | Interleaved calls keep state |

### 5. il_string_similarity type safety (Sprint 4) — 6 tests

| Test | What it verifies |
|------|-----------------|
| `rejects non-character input` | Numeric, logical inputs error |
| `rejects vector input` | `c("a","b")` errors |
| `two empty strings` | `levenshtein("","") == 0` |
| `both NA returns all NA` | All columns are `NA` |

### 6. il_completeness edge cases (Sprint 5) — 6 tests

| Test | What it verifies |
|------|-----------------|
| `all-NA column reports 0%` | `pct_non_null == 0` |
| `single-column data frame` | Returns one row |
| `two tables returns rows for both` | `table_1` and `table_2` in output |

### 7. il_count_pairs edge cases (Sprint 5) — 4 tests

| Test | What it verifies |
|------|-----------------|
| `all-unique blocking column → 0 pairs` | No duplicates = no pairs |
| `single-row dedupe → 0 pairs` | Cannot pair with self |

### 8. il_model validation and contracts (Sprint 6) — 6 tests

| Test | What it verifies |
|------|-----------------|
| `missing columns error` | Spec references nonexistent column |
| `stores data dimensions` | `n_records_l` matches input |
| `print returns model invisibly` | `print(model)` → invisible model |

### 9. NA tolerance in training (Sprint 7) — 5 tests

| Test | What it verifies |
|------|-----------------|
| `EM tolerates NA in non-blocking columns` | Training succeeds, params ∈ [0,1] |
| `il_weights() column contract` | Has comparison, level, weight |
| `il_parameters() returns m/u per level` | Each comparison has match + non_match |

### 10. predict boundaries and dplyr compat (Sprint 8) — 16 tests

| Test | What it verifies |
|------|-----------------|
| `threshold = 1.0 is restrictive` | Fewer pairs than at 0.5 |
| `output is deterministic` | Two calls return same rows |
| `il_compared supports select, arrange, slice` | dplyr verbs work |
| `il_find_matches() with no match → 0 rows` | No blocking match = empty |
| `il_waterfall() has step, contribution, direction` | Column contract |
| `il_deterministic_link() in a pipe` | Works without trained model |
| `predict() handles NA in comparison columns` | No crash, probs ∈ [0,1] |

### 11. Clustering edge cases (Sprint 9) — 8 tests

| Test | What it verifies |
|------|-----------------|
| `cluster IDs are unique per cluster` | Two disconnected pairs → 2 clusters |
| `isolates records below threshold` | C isolated when B-C is below threshold |
| `invalid method rejected` | `method = "invalid"` errors |
| `graph_metrics single-node density = 1` | 2 nodes, 1 edge → density 1.0 |
| `graph_metrics returns three named elements` | nodes, edges, clusters |

### 12. Evaluation and serialization (Sprint 10) — 10 tests

| Test | What it verifies |
|------|-----------------|
| `all-positive labels → 0 FP at threshold 0` | Consistency check |
| `il_errors() has error_type column` | Distinguishes FP from FN |
| `save/load preserves spec structure` | Comparison columns survive round-trip |
| `corrupted JSON errors informatively` | Invalid file → clear error |
| `autoplot dispatches via ggplot2::autoplot()` | S3 method registration works |

---

## What is NOT tested (deferred)

These were considered but intentionally left for future stages:

| Category | Reason deferred |
|----------|----------------|
| Snapshot tests for print/summary output | Stage 6 (need stable output format) |
| Backend compatibility (PostgreSQL, DuckDB) | Stage 6 (environment limitation) |
| Performance benchmarks (>10k records) | Stage 7 |
| Non-ASCII / UTF-8 string similarity | Low priority, stringdist handles |
| magrittr `%>%` compatibility | Works via tibble inheritance |
| Very large model serialization | Low priority |
| SQL injection in cl_custom() | Out of scope for unit tests |
