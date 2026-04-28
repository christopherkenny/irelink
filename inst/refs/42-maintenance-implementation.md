# Splink 5 Maintenance Implementation Log

This log records the implementation work following
`41-maintenance-investigation.md`. Each section is appended after the feature is
implemented and focused tests have been run.

## 1. Unique Prior Counting

Implemented the first maintenance item: `il_estimate_prior()` now counts unique
blocked pairs across all deterministic rules instead of summing each rule's
count independently.

Files changed:

- `R/utils-sql.R`
  - Added `blocked_pair_rows_sql()`.
  - Added `count_unique_blocked_pairs()`.
  - The helper uses `build_table_pairs()` so dedupe, link, and
    link-and-dedupe use the same pair eligibility rules as prediction.
  - Unique identity includes source side and record ID:
    `(source_l, unique_id_l, source_r, unique_id_r)`.
- `R/il_estimate_prior.R`
  - Added strict `recall` validation: finite scalar with `0 < recall <= 1`.
  - Rejects non-`il_blocking_rule` inputs.
  - Uses `count_unique_blocked_pairs()`.
  - Corrects the `link_and_dedupe` denominator to include cross-table,
    within-left, and within-right possible pairs.
- `tests/testthat/test-il_estimate.R`
  - Added an overlapping-rule test proving duplicate pairs are counted once.
  - Added recall validation coverage.
  - Added link-mode prior coverage.
  - Added link-and-dedupe denominator coverage.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-il_estimate.R")
```

Result: passed, `18` expectations.

## 2. Model-Scoped Table Lifecycle and `il_cleanup_all()`

Implemented the table-lifecycle foundation.

Files changed:

- `R/utils-register.R`
  - Added `il_new_table_prefix()` and `il_table_suffix()`.
  - Added `il_table_name()` for model-scoped internal table names.
  - Added lightweight table tracking helpers:
    `il_track_table()`, `il_drop_tracked()`, and
    `il_table_belongs_to_model()`.
- `R/il_model.R`
  - `il_model()` and `il_attach()` now allocate a model table prefix.
  - Registered source tables use model-scoped names instead of shared
    `__il_data_l` / `__il_data_r`.
  - Model metadata stores `data$table_prefix` and a table registry for source
    tables.
- `R/predict.R`
  - Lazy prediction tables now use model-scoped generated names.
  - Dependency-aware temporary score tables now use model-scoped generated
    names.
- `R/il_cleanup.R`
  - `il_cleanup(model)` now removes tables known to belong to the model:
    source tables, TF tables, tracked tables, and any table with the model
    prefix.
  - Added exported `il_cleanup_all(con)` as the explicit broad cleanup helper
    for interactive sessions and failed runs.
- `NAMESPACE`
  - Exported `il_cleanup_all`.
- `tests/testthat/test-table-lifecycle.R`
  - Added coverage for two models sharing one connection.
  - Added coverage for `il_cleanup_all(con)`.
  - Added coverage for model-prefixed lazy prediction tables.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-table-lifecycle.R")
testthat::test_file("tests/testthat/test-il_model.R")
testthat::test_file("tests/testthat/test-register-data.R")
```

Result: passed, `46` expectations across the three files.

## 3. Model-Specific Term-Frequency Tables

Implemented model-specific TF table registration and lookup.

Files changed:

- `R/utils-tf.R`
  - `compute_tf_tables()` now writes model-scoped TF tables via
    `il_table_name(model, "tf", col)`.
  - Computed TF tables are tracked in `model$data$tables`.
  - `sql_tf_select_exprs()` now requires a named `tf_tables` registry instead
    of constructing hard-coded `__il_tf_<col>` names.
  - `lookup_tf_r()` reads TF tables from `model$data$tf_tables`.
- `R/utils-sql.R`
  - `build_gamma_query()` passes `model$data$tf_tables` into
    `sql_tf_select_exprs()`.
- `R/il_find_matches.R`
  - Uses a model-scoped temporary table for incoming records.
  - Passes `model$data$tf_tables` into `sql_tf_select_exprs()`.
- `R/il_register_tf.R`
  - Writes pre-computed TF lookup data to a model-scoped table.
  - Updates `model$data$tf_tables`.
  - Returns the updated model visibly.
- `R/il_tf_chart.R`
  - Resolves the TF table from `model$data$tf_tables`.
- `tests/testthat/test-term-frequency.R`
  - Updated expectations for model-scoped TF names.
  - Added coverage proving two models can use TF on the same column in one
    connection without table collisions.
- `tests/testthat/test-register-tf.R`
  - Updated for model-scoped registered TF tables.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-term-frequency.R")
testthat::test_file("tests/testthat/test-register-tf.R")
testthat::test_file("tests/testthat/test-il_tf_chart.R")
testthat::test_file("tests/testthat/test-il_attach.R")
```

Result: passed, `73` expectations across the four files.

## 4. Explicit Match-Weight Semantics

Implemented the match-weight decision from the investigation: keep
`match_weight` as the R-facing, evidence-only log2 Bayes factor and add
`total_match_weight` for the prior-inclusive posterior log2 odds used by
Splink 5 threshold terminology.

Files changed:

- `R/utils-scoring.R`
  - Added `prior_match_weight()`.
  - Added `total_match_weight()`.
- `R/utils-sql.R`
  - SQL prediction now emits `total_match_weight`.
  - Greedy lazy prediction preserves `total_match_weight`.
  - `threshold_match_weight` continues to filter on evidence-only
    `match_weight`.
- `R/predict.R`
  - Collected and lazy prediction outputs now include
    `total_match_weight`.
  - Empty prediction outputs include the same column set as non-empty
    outputs.
  - Documentation states the distinction between evidence-only
    `match_weight` and prior-inclusive `total_match_weight`.
- `R/utils-dependency-aware.R`
  - Dependency-aware pattern scoring now emits `total_match_weight`.
  - Dependency-aware SQL lookup tables include `total_match_weight`.
- `R/il_find_matches.R`
  - Incremental matching now emits `total_match_weight` on SQL and R paths.
- `R/il_score_missing_edges.R`
  - Missing-edge scoring now emits `total_match_weight`.
- `man/predict.il_model.Rd`
  - Updated generated-facing documentation manually to match the roxygen
    source.
- `tests/testthat/test-predict.R`
  - Added coverage for the identity
    `total_match_weight = match_weight + log2(prior / (1 - prior))`.
  - Added coverage that `match_probability` is the logistic transform of
    `total_match_weight`.
  - Added lazy greedy parity coverage for `total_match_weight`.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-predict.R")
testthat::test_file("tests/testthat/test-dependency-aware-scoring.R")
testthat::test_file("tests/testthat/test-il_score_missing_edges.R")
testthat::test_file("tests/testthat/test-il_waterfall.R")
testthat::test_file("tests/testthat/test-il_attach.R")
```

Result: passed, `95` expectations across the five files.

## 5. Chunked `il_estimate_u()`

Implemented opt-in chunking and early stopping for u estimation.

Files changed:

- `R/il_estimate_u.R`
  - Added `min_count_per_level` and `chunk_size` arguments.
  - Preserved the existing single-query behavior when both
    `min_count_per_level` and `chunk_size` are `NULL`.
  - Added validation for count-like arguments.
  - Stores `model$params$u_estimation` metadata:
    `n_pairs_sampled`, `stopped_early`, `min_count_per_level`,
    `chunk_size`, `max_pairs`, and `n_chunks`.
- `R/utils-em.R`
  - Added `get_random_pair_gamma_counts_chunked()`.
  - Added gamma-count helpers:
    `empty_gamma_counts()`, `gamma_matrix_counts()`,
    `combine_gamma_counts()`, and `gamma_support_met()`.
  - DuckDB/PostgreSQL path chunks the same table-pair stream used by the old
    estimator with `LIMIT ... OFFSET ...`, accumulating pattern counts.
  - SQLite/R fallback chunks after collecting the deterministic pair stream,
    which keeps semantics available for tests and small examples even though
    it does not provide the same database-planner benefit.
- `tests/testthat/test-il_estimate.R`
  - Added an early-stop test with `min_count_per_level = 1`.
  - Added a full-chunk equivalence test against the old estimator.
  - Added a two-table link-mode chunking test.
  - Added coverage that unobserved multi-level comparison states remain in the
    parameter table with the existing `1e-6` u floor.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-il_estimate.R")
```

Result: passed, `29` expectations.

## 6. Materialized Blocked Pairs

Implemented an internal blocked-pairs materialization path for prediction.

Files changed:

- `R/utils-em.R`
  - Added `register_blocked_pairs()`.
  - The registered table contains only pair identity columns:
    `source_l`, `l_unique_id`, `source_r`, and `r_unique_id`.
  - Tables are model-scoped via `il_table_name()` and tracked for
    `il_cleanup(model)`.
  - The helper returns the updated model with
    `model$data$blocked_pairs[[purpose]]` populated.
- `R/utils-sql.R`
  - `build_gamma_query()` now accepts `blocked_pairs_tbl`.
  - Added `build_gamma_query_from_blocked_pairs()` to join a materialized pair
    table back to the source tables and compute gamma columns.
  - The materialized path supports dedupe, link, and link-and-dedupe by using
    the stored source-side columns.
- `R/predict.R`
  - Collected SQL prediction and lazy prediction use
    `model$data$blocked_pairs[["predict"]]` when it exists.
  - Dependency-aware SQL prediction also uses the registered pair table when
    present.
- `tests/testthat/test-blocked-pairs.R`
  - Added overlapping-rule deduplication coverage.
  - Added dedupe, link, and link-and-dedupe coverage.
  - Added character-ID and raw `.where` blocking coverage.
  - Added prediction parity coverage comparing results with and without a
    registered blocked-pairs table.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-blocked-pairs.R")
```

Result: passed, `10` expectations.

## 7. Lightweight SQL Profiling

Implemented the profiling wrapper item after the main query boundaries were
stable.

Files changed:

- `R/utils-db.R`
  - Added `il_new_sql_profile()`.
  - Added `il_db_execute()` and `il_db_get_query()` wrappers around DBI calls.
  - Added `il_sql_profile_entries()` to return profile entries as a tibble.
- `R/il_estimate_u.R`
  - Added `profile_sql`.
  - When enabled, stores timing metadata in `model$params$sql_profile`.
- `R/utils-em.R`
  - `get_random_pairs_with_gammas()` and the SQL branch of
    `get_random_pair_gamma_counts_chunked()` use the profiled query wrapper.
- `R/il_estimate_prior.R`
  - Added `profile_sql`.
  - When enabled, stores timing metadata in `model$params$sql_profile`.
- `R/utils-sql.R`
  - `count_unique_blocked_pairs()` uses the profiled query wrapper when a
    profile collector is supplied.
- `R/predict.R`
  - Added `profile_sql`.
  - Collected SQL predictions attach a `sql_profile` attribute.
  - Lazy SQL predictions store a `sql_profile` tibble on the
    `il_compared_lazy` object.
- `R/utils-classes.R`
  - `new_il_compared_lazy()` accepts and stores `sql_profile`.
- `man/il_estimate_u.Rd`, `man/il_estimate_prior.Rd`, and
  `man/predict.il_model.Rd`
  - Updated manually to match the new roxygen source.
- `tests/testthat/test-sql-profile.R`
  - Added DuckDB coverage for profiled `il_estimate_u()`,
    `il_estimate_prior()`, collected `predict()`, and lazy `predict()`.

Focused verification:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-sql-profile.R")
```

Result: passed, `8` expectations.

## Full Test Pass

Ran the full test suite after the seven maintenance implementation steps:

```r
devtools::load_all()
testthat::test_dir("tests/testthat")
```

Result: passed, `956` expectations; `10` tests skipped because they are marked
for CRAN skipping. A later follow-up pass after the lifecycle review fixes
passed `962` expectations with the same `10` CRAN skips; see section 9.

Packaging checks:

- `tools::checkRd()` passed for the updated manual pages:
  `man/il_estimate_u.Rd`, `man/il_estimate_prior.Rd`, and
  `man/predict.il_model.Rd`.
- `devtools::check(document = FALSE, args = c("--no-manual",
  "--no-build-vignettes"), error_on = "never")` was attempted but exceeded the
  10-minute tool timeout, so there is no completed package-check result from
  this pass.

## 8. User-Facing Documentation Propagation

Propagated the maintenance changes into the main user-facing surfaces:
README, vignettes, `inst/benchmarks`, manual pages, and pkgdown.

The updates clarify that `predict(threshold = ...)` is probability-based,
document the evidence-only `match_weight` versus prior-inclusive
`total_match_weight`, describe when to use model-scoped `il_cleanup(model)`
versus broad `il_cleanup_all(con)`, and add advanced examples for chunked
`il_estimate_u()` and `profile_sql`.

`il_cleanup_all` is now listed in `_pkgdown.yml`, has an Rd page, and benchmark
scripts call it before disconnecting where broad cleanup is appropriate.
Verification: README rendered, updated Rd pages passed `tools::checkRd()`, and
focused table-lifecycle / SQL-profile tests passed.

## 9. Lifecycle Review Follow-Ups

Addressed two review findings from the unpushed maintenance changes.

Files changed:

- `R/predict.R`
  - Collected dependency-aware SQL prediction now allocates a model-scoped
    generated score lookup table instead of using `__il_dependency_scores`.
- `R/il_find_matches.R`
  - Dependency-aware incremental matching now allocates a model-scoped
    generated score lookup table instead of using
    `__il_find_dependency_scores`.
- `R/utils-dependency-aware.R`
  - `prepare_dependency_scored_query()` and `dependency_write_score_lookup()`
    now generate model-scoped score table names when callers do not supply one.
- `R/utils-sql.R`
  - `blocked_pair_rows_sql()` now applies `sql_explode_from()` so unique prior
    counting and materialized blocked pairs honor `.explode` blocking rules,
    matching ordinary prediction SQL.
- `tests/testthat/test-blocked-pairs.R`
  - Added DuckDB coverage proving exploded array blocking works through both
    `register_blocked_pairs()` and `il_estimate_prior()`.
- `tests/testthat/test-dependency-aware-scoring.R`
  - Added sentinel-table coverage proving collected dependency-aware prediction
    and `il_find_matches()` do not touch the old shared score lookup table names.

Focused verification:

```r
devtools::load_all(quiet = TRUE)
testthat::test_file("tests/testthat/test-blocked-pairs.R")
testthat::test_file("tests/testthat/test-dependency-aware-scoring.R")
testthat::test_file("tests/testthat/test-predict.R")
```

Result: passed, `77` expectations.

Full verification:

```r
devtools::load_all(quiet = TRUE)
testthat::test_dir("tests/testthat")
```

Result: passed, `962` expectations; `10` tests skipped because they are marked
for CRAN skipping.

## 10. Standalone Scratch-Table Name Follow-Up

Addressed the remaining table-lifecycle review note: standalone diagnostic and
helper paths no longer reuse fixed `__il_*` scratch table names on a shared
connection. These are mostly call-scoped tables that already cleaned up with
`on.exit()`, but generated names remove collision risk for repeated, nested, or
interrupted workflows.

Files changed:

- `R/utils-register.R`
  - Added `il_scratch_table_name()` for generated package scratch names that
    still use the `__il_` prefix so `il_cleanup_all(con)` can clear them.
- `R/il_profile.R`
  - Replaced `__il_profile_tmp` with a generated scratch name.
- `R/il_largest_blocks.R`
  - Replaced `__il_largest_tmp` with a generated scratch name.
- `R/il_compare_records.R`
  - Replaced `__il_compare_records` with a generated scratch name.
- `R/il_comparator_score.R`
  - Replaced `__il_comparator_tmp` and `__il_phonetic_tmp` with generated
    scratch names.
- `R/il_deterministic_link.R`
  - Replaced `__il_det_data` with a generated scratch name.
- `R/il_count_pairs.R`
  - Replaced `__il_pairs_l` and `__il_pairs_r` with generated scratch names.
- `R/il_suggest_blocking.R`
  - Replaced `__il_suggest` and `__il_bfl` with generated scratch names.
- `R/il_completeness.R`
  - Replaced fixed completeness table names with generated scratch names.
- `R/il_estimate_m_from_labels.R` and `R/utils-evaluation.R`
  - Replaced fixed label upload tables with model-scoped generated names.
- `R/utils-cc.R`, `R/il_cluster.R`, `R/il_cluster_confusion_matrix.R`, and
  `R/il_graph_metrics.R`
  - Connected-component SQL internals now use a generated per-operation prefix
    that is threaded through edges, representatives, best-link, output, and
    graph-metric tables.
- `tests/testthat/test-sql-clustering.R`
  - Updated cleanup expectations for generated connected-component prefixes.

Focused verification:

```r
devtools::load_all(quiet = TRUE)
testthat::test_file("tests/testthat/test-sql-clustering.R")
testthat::test_file("tests/testthat/test-il_cluster.R")
testthat::test_file("tests/testthat/test-il_cluster_confusion_matrix.R")
testthat::test_file("tests/testthat/test-il_graph_metrics.R")
testthat::test_file("tests/testthat/test-il_profile.R")
testthat::test_file("tests/testthat/test-il_count_pairs.R")
testthat::test_file("tests/testthat/test-suggest-blocking.R")
testthat::test_file("tests/testthat/test-il_estimate.R")
testthat::test_file("tests/testthat/test-comparator-score.R")
testthat::test_file("tests/testthat/test-il_completeness.R")
testthat::test_file("tests/testthat/test-il_deterministic_link.R")
testthat::test_file("tests/testthat/test-il_compare.R")
```

Result: all focused tests passed. A follow-up source search found no remaining
fixed scratch assignments for the reviewed names:
`__il_profile_tmp`, `__il_largest_tmp`, `__il_compare_records`,
`__il_comparator_tmp`, `__il_phonetic_tmp`, `__il_det_data`, `__il_pairs_l`,
`__il_pairs_r`, `__il_suggest`, `__il_bfl`, `__il_eval_labels`,
`__il_m_labels`, or the old fixed `__il_cc_*` connected-component names.
