# Stage 8 — Polishing (Executive Summary)

## Objective

Polish the irelink package for real-world use: close performance gaps,
achieve feature parity with splink, add real demo data and plots, and
make the data input API more flexible.

## Approach

1. **Profiled and optimised** the full pipeline (R-side vectorisation,
   then SQL-first gamma computation for DuckDB)
2. **Audited** all places where data was pulled into R unnecessarily and
   pushed computation back into SQL
3. **Checked feature parity** against splink tutorials 02–08 and the
   rl-bootcamp demo, then filled the remaining gaps
4. **Replaced synthetic demo data** with the real splink datasets and
   added `autoplot()` methods for all evaluation outputs
5. **Extended the data input API** to accept lazy database references
   and table name strings in addition to data frames

## Key Changes

### Performance (refs 15–16)

Two rounds of optimisation:

**R-side (stage 7a):** Replaced the R union-find in `il_cluster()` with
`igraph::components()` (1,000× faster at 100K edges), rewrote EM and
scoring loops as matrix multiplies (8×), rewrote `il_find_matches()` to
use a single batched SQL join instead of a row-by-row loop, and fixed
`score_labeled_pairs()` to score only the labelled pairs directly.

**SQL-first (stage 7b):** Pushed gamma (comparison) computation into
DuckDB using native C++ string functions (`jaro_winkler_similarity()`,
`levenshtein()`, etc.), eliminating the dominant bottleneck of pulling
all pairs into R. SQLite retains the R-side `stringdist` fallback
transparently.

| N | Original SQLite | Final DuckDB SQL-first | Total speedup |
|---:|----------------:|-----------------------:|--------------:|
| 1,000 | 2.9 s | 1.4 s | **2.1×** |
| 5,000 | 31.6 s | 19.5 s | **1.6×** |
| 10,000 | 157 s | 61.4 s | **2.6×** |

### SQL push-down audit (ref 17)

Audited every function that called `DBI::dbReadTable()` and replaced
unnecessary full-table reads with targeted SQL joins:

- `il_compare_records()` — ignored its `con` argument; now uses a
  temp-table SQL query on DuckDB and falls back to R-side gamma on
  SQLite.
- `score_labeled_pairs()` — loaded entire source tables to score a
  handful of labelled pairs; now uses a three-way SQL JOIN on DuckDB and
  `WHERE unique_id IN (...)` on SQLite.
- `il_estimate_m_from_labels()` — same fix as above.
- `il_estimate_m_from_column()` SQLite fallback — replaced nested R
  `combn()` loops with a SQL self-join that works on all backends.

`stringdist` remains in `Imports` for the SQLite fallback and the
standalone `il_string_similarity()` function.

### Feature parity (ref 18)

Audited splink tutorials 02–08 and the rl-bootcamp demo. Five gaps were
closed:

1. **`block_on(.where = "SQL")`** — training-time blocking now accepts
   raw SQL conditions (e.g., fuzzy blocking with `levenshtein()`).
2. **`il_estimate_prior()` `.where` passthrough** — correctly forwards
   `.where` to `build_blocking_condition()`.
3. **`il_profile(top_n, bottom_n)`** — column profiling now supports
   limiting to the most and least frequent values.
4. **`il_count_pairs()` cumulative columns** — output now includes
   `cumulative_pairs` and `pct_of_cartesian`.
5. **`il_largest_blocks()`** — new function identifying the largest
   blocking bins by record count.

Interactive HTML dashboards, Spark backend, and salting remain out of
scope.

### Real data and plots (ref 19)

Replaced the procedurally generated `fake_1000` (which incorrectly called
`set.seed()` in package code) with four bundled `.rda` datasets sourced
directly from splink and the FEBRL benchmark:

| Dataset | Rows | Purpose |
|---------|-----:|---------|
| `fake_1000` | 1,000 | Deduplication (181 clusters, ground truth) |
| `fake_1000_labels` | 3,176 pairs | Clerical labels for evaluation |
| `febrl4a` | 5,000 | Cross-table linkage (originals) |
| `febrl4b` | 5,000 | Cross-table linkage (corrupted duplicates) |

Six new `autoplot()` methods were added, dispatching on S3 classes
prepended to evaluation output tibbles:

| Method | What it draws |
|--------|---------------|
| `autoplot.il_model(type = "parameters")` | m/u probabilities faceted by level |
| `autoplot.il_accuracy()` | Precision, recall, F1 vs. threshold |
| `autoplot.il_roc()` | ROC curve |
| `autoplot.il_precision_recall()` | PR curve |
| `autoplot.il_unlinkables()` | Unlinkable proportion vs. threshold |
| `autoplot.il_completeness()` | % non-null per column |

Two new vignettes (`deduplication.Rmd`, `record-linkage.Rmd`) demonstrate
the full workflow using the bundled data. Both build in under 40 seconds.

### Lazy connection support (ref 20)

All major functions now accept three input types for `.data`, mirroring
splink's `_table_registration()` design:

| Input | How it is handled | Copy? |
|-------|-------------------|-------|
| `data.frame` / `tibble` | `dbWriteTable()` | Yes |
| `tbl_lazy` (dbplyr) | `CREATE VIEW` pointing at source | No |
| `character` string | `CREATE VIEW` pointing at named table | No |

The internal `register_data()` helper (in `R/utils-register.R`) handles
all three paths, injects `unique_id` if missing, and extracts the DBI
connection from `tbl_lazy` objects automatically (making `con` optional).
`dbplyr` was added to `Suggests`.

## Test Results

All 460+ tests pass (0 errors, 0 warnings, 0 notes) after all changes.

## References

- Performance profiling: `inst/refs/15-performance-in-r.md`
- SQL-first rewrite: `inst/refs/16-performance.md`
- SQL push-down audit: `inst/refs/17-shove-into-sql.md`
- Feature parity audit: `inst/refs/18-feature-parity.md`
- Tutorial datasets and plots: `inst/refs/19-tutorial-lessons.md`
- Lazy connection support: `inst/refs/20-connections.md`
- Benchmark scripts: `inst/benchmarks/benchmark.R`, `profile.R`, `profile2.R`
