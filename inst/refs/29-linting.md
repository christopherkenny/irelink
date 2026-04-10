# Linting Audit — `jarl check .`

Ran `jarl check .` against the full package. This document records all
findings, resolutions, and the dead-code removal audit.

---

## Summary

| Category | Before | After | Notes |
|----------|--------|-------|-------|
| `internal_function` (`:::` in tests) | 80 | 0 | Removed `irelink:::` prefix; testthat loads namespace |
| `internal_function` (`:::` in benchmarks) | 1 | 1 | Accepted — standalone script needs `:::` |
| `redundant_equals` | 1 | 0 | `== TRUE` → bare logical |
| `any_is_na` | 3 | 0 | `any(is.na())` → `anyNA()` |
| `unused_function` | 2 | 0 | `canonical_pair_key` wired in; `extract_numeric` deleted |
| **Total** | **87** | **1** | Sole remaining: `:::` in benchmark script |

---

## Resolved Lints

### 1. `irelink:::` in tests (80 occurrences → 0)

testthat's `devtools::test()` loads the package namespace, making all
internal functions available without `:::`.

**Files changed:**

| File | Count |
|------|-------|
| `tests/testthat/test-il_phonetic.R` | 30 |
| `tests/testthat/test-register-data.R` | 11 |
| `tests/testthat/test-sql-generate.R` | 10 |
| `tests/testthat/test-cl-time-diff.R` | 7 |
| `tests/testthat/test-explode-blocking.R` | 7 |
| `tests/testthat/test-term-frequency.R` | 6 |
| `tests/testthat/test-il_transform.R` | 5 |
| `tests/testthat/test-transform.R` | 4 |

### 2. `redundant_equals` (1 → 0)

```r
# Before (R/il_estimate_m_from_labels.R:79)
match_pairs <- labels[labels$is_match == TRUE, ]

# After
match_pairs <- labels[labels$is_match, ]
```

### 3. `any_is_na` (3 → 0)

Replaced `any(is.na(...))` with `anyNA(...)` — avoids allocating a
full logical vector.

| File | Line |
|------|------|
| `R/utils-comparison-helpers.R` | 12 (`check_similarity_thresholds`) |
| `R/utils-comparison-helpers.R` | 36 (`check_distance_thresholds`) |
| `R/utils-sql.R` | 122 (`transform_to_name`) |

### 4. `canonical_pair_key` — wired into production

`canonical_pair_key(id_l, id_r)` in `R/utils-evaluation.R` creates
canonical pair keys (`pmin(l,r) || pmax(l,r)`) for unordered pairs.

**Problem:** `il_score_missing_edges.R` reimplemented the same
`pmin`/`pmax` logic inline.

**Fix:** Replaced inline code with `canonical_pair_key()` call (both
existing-pair set and combo-pair keys).

---

## Dead Code Removed

Full audit of every internal function in `R/`. Criteria: if a function
defined in `R/` is never called from `R/` code, it must either be wired
in or deleted. Test-only usage does not justify keeping a function —
tests should test behaviour that users exercise, not internal mechanics
for their own sake.

### Deleted Functions

| Function | File | Why it existed | Why it was removed |
|----------|------|---------------|--------------------|
| `extract_numeric` | `R/utils-unit-helpers.R` | Generic extractor for unit helpers | Never called. `cl_time_diff`, `cl_date_diff`, `cl_distance_km` each do domain-specific extraction with tailored validation. |
| `transform_has_sql` | `R/utils-sql.R` | Predicate: "can this transform be pushed to SQL?" | Never used for any decision. `sql_transform_col()` just tries each path. The predicate validated nothing user-facing. |
| `sql_for_blocking_rule` | `R/utils-sql.R` | Early SQL fragment generator for a single blocking rule | Superseded by `build_blocking_condition()`, which handles transforms, `WHERE` clauses, and dialect differences. |
| `sql_for_blocking_rules` | `R/utils-sql.R` | OR-composed wrapper over `sql_for_blocking_rule` | Superseded — same as above. |
| `sql_join_condition` | `R/utils-sql.R` | Dedupe (`<`) vs link (`<>`) join fragment | Logic is inlined in `build_gamma_query()` (lines 645, 662, 666) where it's actually used. |
| `cc_cleanup` | `R/utils-cc.R` | Drop `__il_cc_*` temp tables | `cc_sql()` already cleans up intermediate tables at lines 229–236. This was a redundant test helper. |

### Deleted Tests (13 tests)

Tests that existed solely to exercise the deleted functions:

| Test file | Tests removed |
|-----------|---------------|
| `test-column-transforms.R` | "column transforms report SQL availability" (6 expects), `transform_has_sql(tf)` line in compose test |
| `test-il_transform.R` | "transform_has_sql works for chains" |
| `test-sql-generate.R` | "block_on() generates equality SQL", "multiple blocking rules produce OR-composed SQL", "block_on(col1, col2) produces AND-composed SQL", "dedupe join condition excludes self-pairs", "link-only join condition pairs records across datasets" |

The `test-sql-clustering.R` test that used `cc_cleanup` was updated to
inline the 3-line cleanup logic directly in the test.

---

## Accepted Exception

### `:::` in `inst/benchmarks/profile.R`

Benchmark scripts under `inst/` run outside the testthat framework as
standalone R scripts. `:::` is the correct way to access internal
functions in this context.

---

## Post-Lint Results

```
jarl check .   → 1 warning (benchmark :::)

devtools::check()
0 errors ✔ | 0 warnings ✔ | 0 notes ✔

devtools::test()
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 847 ]
```
