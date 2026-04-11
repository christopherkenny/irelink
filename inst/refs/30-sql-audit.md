# SQL Materialisation Audit

Audit of every `DBI::dbGetQuery()` call in `R/` to identify sites where
R-side aggregation, counting, or filtering should be pushed into SQL.
Cross-referenced against splink's SQL patterns.

## Key Architectural Insight (from splink)

Splink's EM implementation (`splink/internals/expectation_maximisation.py`)
**never materialises pair-level gamma data into Python**.  Instead:

1. Agreement patterns are aggregated in SQL via
   `GROUP BY gamma_cols, COUNT(*) AS agreement_pattern_count`
   (`expectation_maximisation.py:27–41`).
2. The E-step runs entirely in SQL (`predict_from_agreement_pattern_counts_sqls`).
3. The M-step aggregates weighted counts in SQL
   (`compute_new_parameters_sql`, lines 44–85) and only pulls the tiny
   aggregated parameter summary into Python.
4. `predict()` returns a `SplinkDataFrame` referencing a database table —
   users must explicitly call `as_pandas_dataframe()` to materialise.

irelink had the same general structure (lazy vs collected paths) but
several functions still pulled full pair-level data into R for trivial
aggregation that SQL can handle.

---

## Sites Fixed

### 1. `il_estimate_em()` — EM with aggregated gamma counts

**File:** `R/il_estimate_em.R` (line 100), `R/utils-em.R` (new
`get_pairs_with_gamma_counts`)

**Before:** Called `get_pairs_with_gammas()` which pulled the full
pair-level gamma matrix into R (potentially millions of rows for 50k
records).  The EM loop operated on every row individually.

**After:** New function `get_pairs_with_gamma_counts()` wraps
`build_gamma_query()` in `SELECT gamma_cols, COUNT(*) AS n … GROUP BY
gamma_cols`, returning only the unique gamma patterns (typically
100–1000 rows).  The EM loop now multiplies by pattern counts:

- E-step: `weights` computed per *pattern*, not per pair
- M-step: `sum(weights[mask] * pattern_n[mask])` replaces
  `sum(weights[mask])`
- `derive_prior_from_params()` uses weighted average

**Impact:** For 5M pairs with 6 comparisons and ~500 unique gamma
patterns, data transfer drops from ~240 MB to ~4 KB.  EM iterations
also run on ~500 rows instead of ~5M.

**Splink equivalent:** `count_agreement_patterns_sql()` at
`expectation_maximisation.py:27–41`.

**Status:** ✅ Resolved

---

### 2. `il_estimate_m_from_column()` — level counting in SQL

**File:** `R/il_estimate_m_from_column.R` (lines 44–67)

**Before:** DuckDB path pulled the full gamma matrix into R, then
counted level frequencies with `sum(gamma_mat[, j] == k) / n_pairs`.

**After:** SQL query wraps gamma computation in
`GROUP BY gamma_cols, COUNT(*) AS n`.  Only the tiny aggregated counts
cross the boundary.  R-side fallback (SQLite) also aggregates via
`aggregate()` before counting.

**Status:** ✅ Resolved

---

### 3. `il_estimate_m_from_labels()` — level counting in SQL

**File:** `R/il_estimate_m_from_labels.R` (lines 84–112)

**Before:** Same pattern as `il_estimate_m_from_column` — pulled full
gamma matrix, counted in R loops.

**After:** SQL aggregation via `GROUP BY gamma_cols, COUNT(*) AS n`.

**Status:** ✅ Resolved

---

### 4. `labels_from_column()` — lazy prediction + SQL label join

**File:** `R/utils-evaluation.R` (lines 35–49)

**Before:** Called `predict(model, threshold = 0)` with `collect = TRUE`,
materialising ALL candidate pairs into R.  For 50k records this could
be millions of pairs.  Then called `resolve_labels_from_pairs()` which
fetched ground truth into R and did rowname-based matching.

**After:** DuckDB path calls `predict_lazy()` to keep scored pairs in
SQL, then resolves labels via a single SQL JOIN:

```sql
SELECT p.unique_id_l, p.unique_id_r,
  CASE WHEN gl.label_col IS NOT NULL
    AND gr.label_col IS NOT NULL
    AND gl.label_col = gr.label_col THEN 1 ELSE 0 END AS is_match
FROM __il_predicted p
JOIN data_tbl gl ON gl.unique_id = p.unique_id_l
JOIN data_tbl gr ON gr.unique_id = p.unique_id_r
```

Only the small labels frame (one row per pair with `is_match`) crosses
the boundary.

**Impact:** Eliminates the single largest bottleneck when using
`labels_col` in `il_accuracy()`, `il_errors()`, `il_roc()`, and
`il_precision_recall()`.

**Splink equivalent:** `_predict_from_label_column_sql()` at
`accuracy.py:533–536` keeps predictions in SQL.

**Status:** ✅ Resolved

---

### 5. `score_labeled_pairs()` — scoring pushed to SQL

**File:** `R/utils-evaluation.R` (lines 124–214)

**Before:** DuckDB path computed gammas in SQL (good) but pulled the
gamma matrix into R, then scored with `score_gamma_matrix()` in R.

**After:** DuckDB path now builds the full scoring expression in SQL
using `sql_weight_case()` (the same infrastructure as
`build_scored_query()`).  The SQL query computes `match_weight` and
`match_probability` in-database and returns only the small scored
result.  No gamma matrix crosses the boundary.

**Status:** ✅ Resolved

---

### 6. `join_original_fields()` — SQL JOIN path

**File:** `R/predict.R` (lines 224–273)

**Before:** Pulled all source records for unique IDs into R, then did
rowname-based column lookups in R loops.  For large result sets this
materialised the full source table.

**After:** DuckDB path uploads result IDs to a temp table, JOINs to
source data in SQL, and returns the joined result directly.  The
`collect = FALSE` path already used `build_fields_join_query()` for
this; now the `collect = TRUE` + `include_fields = TRUE` path also
avoids the R-side rowname lookup.

**Splink equivalent:** `predict()` keeps results in SQL; field
inclusion is handled by `SplinkDataFrame` column selection.

**Status:** ✅ Resolved

---

## Sites Reviewed — No Change Needed

### `get_pairs_with_gammas()` — `R/utils-em.R:23`

Pulls full gamma matrix + TF data into R.  Used by `predict()` with
`collect = TRUE` (line 121 of `predict.R`).  The user explicitly
requests an in-memory tibble, so materialisation is intentional.
The lazy path (`predict_lazy`) already pushes everything to SQL.

EM training no longer calls this function — it uses the new
`get_pairs_with_gamma_counts()` instead.

**Status:** ⬜ Correct — intentional materialisation for collected output

---

### `get_random_pairs_with_gammas()` — `R/utils-em.R:144`

Already fixed in a prior session.  Uses `GROUP BY gamma_cols,
COUNT(*) AS n` to return only aggregated counts.

**Status:** ⬜ Already optimal

---

### `get_blocked_pairs()` / `get_all_pairs()` — `R/utils-em.R:401,427`

SQLite fallback paths only.  DuckDB never takes these paths.

**Status:** ⬜ Fallback only

---

### `il_comparison_vectors()` — `R/il_comparison_vectors.R:53`

Already uses SQL `GROUP BY + COUNT(*)` in the DuckDB path.

**Status:** ⬜ Already optimal

---

### `il_find_matches()` — `R/il_find_matches.R:143`

Pulls gamma matrix for new-vs-existing pairs.  This is the *output*
path (user wants actual matched pairs), and the result set is bounded
by blocking rules + threshold filtering.  A future optimisation could
push scoring into SQL (like `predict_lazy`), but the current approach
is acceptable since `il_find_matches` always returns a small R tibble.

**Status:** ⬜ Acceptable — output-facing function

---

### `il_score_missing_edges()` — `R/il_score_missing_edges.R:78,82`

Fetches source records for a small set of IDs (within-cluster missing
pairs).  The pair set is inherently small and R-side gamma computation
is needed since these pairs weren't in the blocking rules.

**Status:** ⬜ Acceptable — small bounded result

---

### `il_graph_metrics()` — `R/il_graph_metrics.R:114,130`

Fetches node-metric and cluster-metric tables.  These ARE the function
output — small aggregated tables from SQL-side computation.

**Status:** ⬜ Correct — fetching output

---

### `il_deterministic_link()` — `R/il_deterministic_link.R:108`

Fetches pairs for deterministic (exact-match) linking.  Small result
set by nature.

**Status:** ⬜ Acceptable

---

### `il_comparator_score()` — `R/il_comparator_score.R:79,250`

Scores specific record pairs or single comparisons.  Small targeted
queries.

**Status:** ⬜ Acceptable

---

### Scalar / metadata queries

The following all fetch `COUNT(*)` scalars or small metadata:

| File | Line | Purpose |
|------|------|---------|
| `utils-register.R` | 83, 165 | Row count |
| `utils-classes.R` | 210 | Lazy pair count |
| `il_count_pairs.R` | 166 | Pair count per rule |
| `il_suggest_blocking.R` | 109, 115 | Distinct/coverage counts |
| `utils-cc.R` | 156, 190 | CC iteration counts |
| `il_largest_blocks.R` | 79 | Block sizes (aggregated) |

**Status:** ⬜ All correct — small aggregated results

---

### Final-output materialisation

| File | Line | Purpose |
|------|------|---------|
| `utils-cc.R` | 227 | Final CC assignment table |
| `il_cluster.R` | 319 | Cluster node IDs |
| `utils-classes.R` | 251 | `collect_il_compared_lazy()` — explicit user collect |
| `il_completeness.R` | 77 | Completeness stats |
| `il_profile.R` | 100 | Profile summary |
| `il_tf_chart.R` | 48 | TF distribution data |
| `il_suggest_blocking.R` | 230 | Blocking candidate data |

**Status:** ⬜ All correct — user-facing output

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| Fixed — pushed to SQL | 6 | EM aggregation, m-estimation (×2), label resolution, scoring, field joins |
| Already optimal | 3 | `get_random_pairs_with_gammas`, `il_comparison_vectors`, prior u-estimation |
| Intentional materialisation | 2 | `predict(collect=TRUE)`, `collect_il_compared_lazy()` |
| Fallback-only (SQLite) | 2 | `get_blocked_pairs`, `get_all_pairs` |
| Output-facing (small) | 14 | Scalar counts, metadata, function outputs |
| Acceptable (bounded) | 3 | `il_find_matches`, `il_score_missing_edges`, `il_deterministic_link` |

All `dbGetQuery` calls now either return SQL-aggregated summaries,
small bounded result sets, or intentional user-requested
materialisations.  No pair-level data is pulled into R for trivial
aggregation that SQL could handle.
