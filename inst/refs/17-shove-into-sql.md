# Issue 17 — Push R-side computation into SQL

> Audit of places where `irelink` materialises data into R that could stay
> inside the SQL backend, and the fixes applied.

## Background

splink's architecture is "generate SQL, ship it to the engine, read back only
aggregates."
Everything from string-distance evaluation through gamma assignment to
Bayes-factor scoring happens in SQL CASE expressions; only the thin EM
parameter-update loop runs in Python.

irelink already follows this pattern for the **primary** (DuckDB / PostgreSQL)
path, but several secondary code paths pull entire tables into R memory and
recompute string distances with the `stringdist` package.
The two signature symptoms were:

1. `il_compare_records()` accepts a `con` argument and never touches it.
2. `score_labeled_pairs()` calls `DBI::dbReadTable()` on the full source tables
   just to score a handful of labelled pairs.

## Findings

### 1. `il_compare_records()` — unused `con` (canary)

`con` was documented and required but completely ignored.
The function built an R-side pair data frame and called
`compute_gamma_matrix()` → `compute_gamma()` → `stringdist::stringdist()`,
even when connected to DuckDB which has native `jaro_winkler_similarity()`,
`levenshtein()`, etc.

**Fix:** When `dialect_has_fuzzy_sql()` is TRUE, upload the two records to a
temp table and run a single SQL query with `sql_gamma_case()` expressions.
Fall back to R-side `compute_gamma_matrix()` only for SQLite.

### 2. `score_labeled_pairs()` — full table reads

Called `DBI::dbReadTable(con, tbl_l)` (and potentially `tbl_r`) to load entire
source tables into R, then row-indexed by `unique_id` to extract the handful
of labelled pairs, then ran R-side gamma computation.

**Fix:** For DuckDB/PostgreSQL, upload the labels to a temp table and run a
three-way JOIN (`labels ⋈ data_l ⋈ data_r`) with in-database gamma CASE
expressions.
For SQLite, use `WHERE unique_id IN (...)` to fetch only the rows actually
referenced by the labels — no full-table scan.

### 3. `il_estimate_m_from_labels()` — full table read + R-side pair loop

Same pattern: `DBI::dbReadTable()` on the full table, then a row-by-row R loop
building pair data frames, then `compute_gamma_matrix()`.

**Fix:** Same two-tier approach as `score_labeled_pairs()`.
DuckDB path: temp label table → SQL JOIN → SQL gamma computation.
SQLite path: `WHERE unique_id IN (...)` to fetch only referenced rows,
then R-side gamma fallback.

### 4. `il_estimate_m_from_column()` SQLite fallback — full table + R loops

The DuckDB path was already SQL-first (self-join with `sql_gamma_case()`).
The SQLite fallback loaded the entire table with `DBI::dbReadTable()`, then
used nested R loops (`for (lab in unique_labels) { combn(cluster, 2) }`) to
enumerate within-cluster pairs.

**Fix:** Replace the R-side pair generation with a SQL self-join:
```sql
SELECT l.*, r.*
FROM tbl l, tbl r
WHERE l.label_col IS NOT NULL AND l.label_col = r.label_col
  AND l.unique_id < r.unique_id
```
This works on every SQL backend (no fuzzy functions needed).
Gamma computation still falls back to R-side `compute_gamma_matrix()` on
SQLite since it lacks native string-distance functions.

## What stays in R (by design)

| Component | Why it stays |
|---|---|
| EM E-step / M-step loop (`il_estimate_em`) | Iterative matrix-vector multiplies; R's BLAS is efficient and the gamma matrix is already in memory from the SQL query. splink does the same (SQL aggregation → Python parameter update). |
| `score_gamma_matrix()` / `weight_to_probability()` | Small vectorised ops on the already-materialised gamma matrix. |
| `il_string_similarity()` | Standalone 2-string utility; no database connection by design. |
| `compute_gamma()` / `compute_gamma_matrix()` | SQLite fallback path; required because SQLite lacks native fuzzy string functions. |

## `stringdist` dependency

`stringdist` remains in `Imports` because:

- `il_string_similarity()` — standalone explorer function, no DB required.
- SQLite fallback in `compute_gamma()` — needed when dialect lacks
  `jaro_winkler_similarity()` etc.

For DuckDB (the primary recommended backend), `stringdist` is never called
during model training or prediction.

## Test results

All 527 tests pass (0 failures, 0 warnings) after the changes.
