# SQL-First Rewrite — Performance Report

## Summary

The original irelink pipeline pulled all record pairs into R and computed
string similarity (jaro-winkler, levenshtein, etc.) R-side via `stringdist`.
This was the dominant bottleneck at scale.
The SQL-first rewrite pushes gamma (comparison level) computation into DuckDB
using its native C++ string similarity functions.
DuckDB is now the default backend for all examples, tests, and vignettes.

**Key results:**

- Test suite: 157 s → 68.6 s (2.3× faster)
- 10K end-to-end benchmark: 113 s → 61.4 s (1.8×, growing with scale)
- devtools::check(): 0 errors, 0 warnings, 0 notes in 3 m 28 s
- 456 tests pass, 0 failures

---

## Architecture Change

### Before

```
SQL cross-join (blocking) → pull ALL pairs to R → R-side stringdist::stringdist()
  → R-side gamma matrix → R-side scoring → R-side threshold filter
```

Every pair was transferred from the database to R, where string comparisons
ran one column at a time through `stringdist`.
For 10K records with 10 distinct surnames, the surname blocking rule alone
produces ~500K pairs — all pulled into R memory.

### After

```
SQL cross-join (blocking) + SQL CASE expressions (gamma) → pull only IDs + gammas
  → R-side matrix scoring → R-side threshold filter
```

DuckDB computes the binary gamma values (0/1) inside the database using native
functions like `jaro_winkler_similarity()`, `levenshtein()`, and standard SQL
for exact/numeric/date comparisons.
Only the compact result (IDs + integer gamma columns) crosses the R-SQL boundary.

For backends without native string functions (SQLite), the old R-side path is
retained as a transparent fallback.

---

## New Internal Functions

### `utils-sql.R`

| Function | Purpose |
|----------|---------|
| `detect_dialect(con)` | Returns `"duckdb"`, `"sqlite"`, `"postgres"`, or `"generic"` |
| `dialect_has_fuzzy_sql(dialect)` | TRUE for DuckDB and PostgreSQL |
| `sql_gamma_case(comp, dialect)` | Binary 0/1 CASE expression for one comparison |
| `build_gamma_query(model, blocking_rules)` | Full SQL: blocking UNION + gamma SELECT + DISTINCT |

### `utils-em.R`

| Function | Purpose |
|----------|---------|
| `get_pairs_with_gammas(model, blocking_rules)` | SQL-first for DuckDB, R fallback for SQLite |
| `get_random_pairs_with_gammas(model, max_pairs)` | Same pattern for U estimation |

Both return a list with `$ids` (data.frame) and `$gamma_mat` (integer matrix),
so downstream consumers don't need to know which path was taken.

---

## Files Modified

| File | Change |
|------|--------|
| `R/utils-sql.R` | Added `detect_dialect`, `sql_gamma_case`, `build_gamma_query` |
| `R/utils-em.R` | Added `get_pairs_with_gammas`, `get_random_pairs_with_gammas` |
| `R/predict.R` | Uses `get_pairs_with_gammas()` instead of loop + `compute_gamma_matrix` |
| `R/il_estimate_em.R` | Uses `get_pairs_with_gammas()` |
| `R/il_estimate_u.R` | Uses `get_random_pairs_with_gammas()` |
| `R/il_find_matches.R` | SQL-first gamma path for DuckDB, R fallback for SQLite |
| `R/il_deterministic_link.R` | Exact-match filter pushed into SQL WHERE clause |
| `R/il_estimate_m_from_column.R` | SQL self-join replaces R-side `combn()` loops |
| `R/il_deterministic_link.R` | Uses `unique_id` instead of `rowid` for deduplication |
| `R/utils-em.R` | `get_blocked_pairs` / `get_all_pairs` use `unique_id` not `rowid` |
| `DESCRIPTION` | Added `duckdb` to Suggests |
| All 26 example files | `RSQLite::SQLite()` → `duckdb::duckdb()` |
| All 16 test files | Use `test_con()` / `test_discon()` helpers |
| `tests/testthat/setup.R` | Added `test_con()` and `test_discon()` helpers |
| `vignettes/irelink.Rmd` | Switched to DuckDB |
| `vignettes/from_splink.Rmd` | Switched to DuckDB |
| `README.Rmd` + `README.md` | Switched to DuckDB |

---

## DuckDB String Functions Used

| Function | Returns | Used for |
|----------|---------|----------|
| `jaro_winkler_similarity(s1, s2)` | float [0, 1] | `cl_jaro_winkler()` |
| `jaro_similarity(s1, s2)` | float [0, 1] | `cl_jaro()` |
| `levenshtein(s1, s2)` | integer distance | `cl_levenshtein()` |
| `damerau_levenshtein(s1, s2)` | integer distance | `cl_damerau_levenshtein()` |
| `ABS(CAST(... AS DOUBLE) - ...)` | float | `cl_numeric_diff()`, `cl_pct_diff()` |
| Standard `=` | boolean | `cl_exact()` |
| `JULIANDAY` / date arithmetic | days | `cl_date_diff()` |

---

## Benchmark Results

### SQL-First DuckDB vs Previous DuckDB (R-side gamma)

| Records | Before (R-side gamma) | After (SQL-first) | Speedup |
|--------:|----------------------:|-------------------:|--------:|
| 1,000 | 1.6 s | 1.4 s | 1.1× |
| 5,000 | 20.8 s | 19.5 s | 1.1× |
| 10,000 | 113 s | 61.4 s | **1.8×** |
| 20,000 | est. 7+ min | 162 s | est. 2.5×+ |

### Full Speedup vs Original SQLite Baseline

| Records | Original SQLite | Final DuckDB SQL-first | Total Speedup |
|--------:|----------------:|-----------------------:|--------------:|
| 1,000 | 2.9 s | 1.4 s | **2.1×** |
| 5,000 | 31.6 s | 19.5 s | **1.6×** |
| 10,000 | 157 s | 61.4 s | **2.6×** |

The speedup increases with dataset size because the pair explosion within
blocking rules is the bottleneck, and DuckDB's native C++ string functions
handle large pair sets much more efficiently than R-side `stringdist`.

### Test Suite

| Metric | Before | After |
|--------|-------:|------:|
| Tests passing | 454 | 456 |
| Test time | 157 s | 68.6 s |
| Check time | 2 m 44 s | 3 m 28 s |
| Check result | 0/0/0 | 0/0/0 |

Check time increased slightly because DuckDB startup adds overhead per
example, but the test suite itself is 2.3× faster.

---

## Design Decisions

### DuckDB as Default

DuckDB is now the default in all examples and tests.
It provides native string similarity functions, columnar storage, and parallel
execution — all critical for record linkage workloads.
SQLite remains supported as a fallback via the R-side gamma computation path.

### Transparent Fallback

The `dialect_has_fuzzy_sql()` check determines the code path at runtime.
No user-facing API changes were needed.
Functions like `predict()`, `il_estimate_em()`, and `il_estimate_u()` work
identically on both backends — the only difference is performance.

### `unique_id` Instead of `rowid`

All self-join deduplication conditions were changed from `l.rowid < r.rowid`
to `l.unique_id < r.unique_id`.
While both DuckDB and SQLite support `rowid`, using the explicit `unique_id`
column is more portable and makes the intent clearer.

---

## Remaining Scaling Concerns

The benchmark uses only 10 distinct surnames and 10 first names, so blocking
rules produce very large blocks (~n/10 records each).
With real data having more diverse blocking keys, pair counts would be
dramatically smaller and performance much better.

For truly large datasets (100K+), further optimisations could include:

1. **Push full scoring into SQL** — compute match weights and threshold
   filtering entirely in DuckDB, returning only matched pairs
2. **DuckDB parallel execution** — the cross-join already benefits from
   DuckDB's multi-threaded engine
3. **Random sampling for U estimation** — `ORDER BY RANDOM() LIMIT n`
   instead of the full cross-join
4. **Salting** — split large blocks into sub-blocks to reduce pair counts
   (a technique used by splink)

---

## References

- `inst/refs/15-performance-in-r.md` — Stage 7a performance review (matrix
  multiply, igraph clustering, batched find_matches)
- `inst/refs/09-implementation-plan.md` — Original implementation roadmap
- Blog post benchmark: <https://www.robinlinacre.com/fast_deduplication/>
