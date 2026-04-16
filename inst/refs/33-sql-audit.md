# SQL Materialisation Audit — Round 2

Audit of every materialization boundary in the core prediction, clustering,
evaluation, and scoring code paths.  Builds on the prior audit in
`inst/refs/30-sql-audit.md`.

## Changes made

### 1. `predict(collect=TRUE)` on DuckDB/PostgreSQL — SQL-first collect

**File:** `R/predict.R:115-134`

Previously, `predict(collect=TRUE)` on DuckDB called `get_pairs_with_gammas()`
which pulled **all** blocked pair-level gamma rows into R (O(pairs) rows × comparisons
columns), then scored, TF-adjusted, and filtered in R.

The `collect=FALSE` (lazy) path already pushed all of this into SQL via
`build_scored_query()`.  Now `collect=TRUE` on DuckDB/PostgreSQL also uses
`build_scored_query()`, so scoring, TF adjustment, deduplication, and threshold
filtering all happen in SQL.  Only the **final filtered result** crosses to R.

On a 1M-pair job where only 10 000 pairs exceed threshold, this reduces the
R-side materialisation from ~1M rows to ~10K.

The SQLite R-side fallback is preserved unchanged (lines 136–202).

### 2. `il_unlinkables()` — SQL path

**File:** `R/il_unlinkables.R:64-110`

Previously called `predict(model, threshold = 0.0)` which materialised every
scored pair into R, then looped 21 thresholds doing R-side filtering and
`unique()`.

Now on DuckDB/PostgreSQL: calls `predict_lazy(threshold = 0)` to keep all
scored pairs in SQL, then runs a single GROUP BY query to get
`MAX(match_probability)` per record ID (collecting only N-records × 1 column).
Threshold comparisons are then vectorised in R on that small vector.

On a 1M-pair / 50K-record job, this reduces the R-side materialisation from
~1M rows to ~50K scalars.

SQLite fallback is preserved.

## Exported-function audit table

| function | sql-first? | materializes to R? | problem | action | notes |
|---|---|---|---|---|---|
| `predict(collect=TRUE)` | **YES** (now) | final filtered pairs only | was pulling all pairs for scoring | **FIXED** — uses `build_scored_query()` on DuckDB/PG | SQLite fallback unchanged |
| `predict(collect=FALSE)` | YES | nothing | — | no change | returns `il_compared_lazy` |
| `il_unlinkables()` | **YES** (now) | max_prob per record (N×1) | was pulling all scored pairs | **FIXED** — SQL `GROUP BY` + `MAX()` | SQLite fallback unchanged |
| `il_cluster()` | YES (lazy path) | final cluster assignments | collected path re-uploads edges via `cc_upload_edges` | no change | users should prefer lazy path; re-upload is from user-requested collect |
| `il_accuracy()` | YES | 1-row confusion matrix | — | no change | tiny aggregate |
| `il_roc()` | YES | ~20 rows (thresholds) | — | no change | tiny aggregate |
| `il_precision_recall()` | YES | ~20 rows (thresholds) | — | no change | tiny aggregate |
| `labels_from_column()` | YES | labeled pairs (~100s–1000s) | — | no change | fixed in prior audit |
| `score_labeled_pairs()` | YES | labeled pairs with scores | — | no change | fixed in prior audit |
| `il_estimate_em()` | YES | gamma-pattern counts (~100–1K rows) | — | no change | fixed in prior audit |
| `il_estimate_m_from_labels()` | YES | labeled gamma counts | — | no change | tiny aggregate |
| `il_estimate_m_from_column()` | YES | labeled gamma counts | — | no change | tiny aggregate |
| `il_estimate_u()` | mixed | gamma counts per comparison | — | no change | small aggregate |
| `il_completeness()` | YES | 1 row per column | — | no change | tiny aggregate |
| `il_waterfall()` | — | operates on collected pairs | requires collected input | no change | input is already in R |
| `il_graph_metrics()` | mixed | uploads collected pairs to SQL | collected pairs re-uploaded | no change | hard to avoid without API change; data already in R |
| `il_score_missing_edges()` | mixed | pair-level | works on collected pairs | no change | input is already in R |
| `il_suggest_blocking()` | YES | profile counts | — | no change | small aggregate |
| `il_find_blocking_below()` | YES | pair counts | — | no change | tiny aggregate |
| `il_largest_blocks()` | YES | block sizes | — | no change | small aggregate |
| `il_profile()` | YES | profile stats | — | no change | small aggregate |
| `il_deterministic_link()` | YES | matched pairs | — | no change | SQL-first |
| `il_find_matches()` | YES | matched pairs | — | no change | SQL-first |
| `il_compare_records()` | YES | scored record pairs | — | no change | SQL-first |
| `il_cluster_confusion_matrix()` | YES | confusion counts | — | no change | SQL-first |

## Sites reviewed but not changed

### `cc_upload_edges()` (utils-cc.R:23-38)
Re-uploads collected pairs to DuckDB for clustering.  This round-trip only
happens when `il_cluster()` receives an `il_compared` (collected) object.
The `cluster_lazy` path avoids it entirely.  Not actionable without an API
change (the user explicitly asked for collected data).

### `graph_metrics_sql()` (il_graph_metrics.R:89-157)
Uploads collected pairs + cluster assignments back to SQL for metric
computation.  The inputs are already in R (user passed collected objects).
Would need a lazy graph_metrics path to avoid.  Low priority.

### `join_original_fields()` (predict.R:246-288)
Uploads result IDs to a temp table, JOINs to source data.  Only reached on
the SQLite R-side fallback path now.  The DuckDB SQL-first collect path uses
`build_fields_join_query()` instead (pure SQL, no round-trip).

### `solve_cc_sql()` final collect (utils-cc.R:~250)
Collects final cluster assignments (N-records × 2).  This is the user-facing
output — necessarily materialised.

### `get_pairs_with_gamma_counts()` (utils-em.R:15-66)
Collects aggregated gamma-pattern rows (typically ~100–1000).  Already
optimised in prior audit; the GROUP BY + COUNT happens in SQL.

## Test results

Full test suite: **PASS 787 | FAIL 0 | WARN 84 | SKIP 0** (48s).
All warnings are expected EM overlap messages in test contexts.
