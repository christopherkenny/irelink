# Splink 5 Maintenance Investigation

This is an implementation-oriented map from the Splink 5 development changelog
to concrete `irelink` maintenance work. The goal is not to clone Splink's Python
object model. It is to keep behavior, performance, and saved-model compatibility
close where that matters, while preserving the R-specific design choices:

- no interactive dashboards as a core dependency;
- DBI connections instead of Splink database backend classes;
- additional statistical features, especially custom priors and
  dependency-aware EM.

Because `irelink` is not yet public, prefer clean breaking changes over
compatibility shims. Do not preserve weak internal APIs just because current
tests exercise them. It is better to settle table naming, cleanup semantics,
term-frequency storage, and match-weight documentation now than to carry
backward-compatibility branches into a first public release.

Primary upstream source:
<https://raw.githubusercontent.com/moj-analytical-services/splink/splink_5_dev/CHANGELOG.md>

Code references below are from Splink commit
`6b729990bc05812885dc05355ecf22999bd14ddc` on `origin/splink_5_dev`.

## Upstream Splink 5 Code References

| Splink 5 change | Upstream code reference | What to copy vs. adapt |
|---|---|---|
| u-estimation exposes early stopping and chunk count | `splink/internals/linker_components/training.py:160-166`, `:192-197`, `:217-223` | Copy the controls concept (`min_count_per_level`, chunks), but keep R defaults conservative. |
| u-estimation implementation samples first, then chunks RHS | `splink/internals/estimate_u.py:330-345`, `:406-427`, `:448-523` | Adapt the stopping criterion and metadata; do not necessarily copy the exact sampled-table/chunk SQL. |
| Precomputed blocked-pairs registration | `splink/internals/linker_components/table_management.py:94-164` | Use as evidence that a blocked-pairs materialization boundary is useful; keep any public R API simpler. |
| `predict()` chunking and registered blocked-pairs workflow | `splink/internals/linker_components/inference.py:220-305`, `:307-365`, `:369-464` | Adapt chunked prediction internally; avoid forcing users into `predict_chunk()` unless needed. |
| Term-frequency lookup table registration | `splink/internals/linker_components/table_management.py:228-275` | Adapt the model-specific table registry idea; do not keep hard-coded `__il_tf_<col>` names. |
| TF tables are pulled into the prediction pipeline when needed | `splink/internals/term_frequencies.py:58-76` | Mirror the lifecycle: prediction should resolve TF tables from model state at scoring time. |
| Prior-inclusive Splink `match_weight` | `splink/internals/predict.py:89-111`, `:203-229` | Treat as a compatibility reference, not automatically the R API choice. |
| `query_sql()` returns `SplinkDataFrame` by default | `splink/internals/linker_components/misc.py:54-85` | Do not copy directly; R should keep DBI/tibble conventions. |
| Broad deletion of Splink-created tables | `splink/internals/database_api.py:368-373`, `splink/internals/linker_components/table_management.py:285-286` | Supports adding `il_cleanup_all(con)`, while keeping `il_cleanup(model)` narrow. |
| Salting and Bayes-factor-prefix deprecations are handled on settings load | `splink/internals/settings_creator.py:118-131`, `:148-154` | Treat old JSON fields as compatibility input; avoid adding salting to `irelink`. |

## Current Code Map

These are the local files that most Splink 5 changes touch.

| Area | Current code | Current tests |
|---|---|---|
| Data/table registration | `R/utils-register.R`: `register_data()`, `drop_registered()` | `tests/testthat/test-register-data.R` |
| Cleanup | `R/il_cleanup.R`: `il_cleanup()` drops all `^__il_` tables | no focused lifecycle test beyond indirect use |
| Blocking SQL | `R/utils-sql.R`: `build_gamma_query()`, `build_table_pairs()`, `build_blocking_condition()`, `count_blocked_pairs()` | `tests/testthat/test-il_count_pairs.R`, `test-explode-blocking.R`, `test-link-and-dedupe.R` |
| Pair generation for EM/u | `R/utils-em.R`: `get_pairs_with_gamma_counts()`, `get_pairs_with_gammas()`, `get_random_pairs_with_gammas()`, `get_blocked_pairs()`, `get_all_pairs()` | `tests/testthat/test-il_estimate.R`, `test-em-*.R` |
| u estimation | `R/il_estimate_u.R`: `il_estimate_u()` | `tests/testthat/test-il_estimate.R` |
| Prior estimation | `R/il_estimate_prior.R`: `il_estimate_prior()` | `tests/testthat/test-il_estimate.R`, `test-em-prior.R` |
| Prediction | `R/predict.R`: `predict.il_model()`, `predict_lazy()`, `greedy_match_pairs()` | `tests/testthat/test-predict.R`, `test-include-fields.R` |
| Scoring SQL | `R/utils-sql.R`: `sql_weight_case()`, `sql_tf_adj_expr()`, `build_scored_query()`, `build_greedy_query()` | `tests/testthat/test-predict.R`, `test-term-frequency.R` |
| Term frequencies | `R/utils-tf.R`, `R/il_register_tf.R`, `R/il_tf_chart.R` | `tests/testthat/test-term-frequency.R`, `test-register-tf.R`, `test-il_tf_chart.R` |
| Dependency-aware scoring | `R/utils-dependency-aware.R`, `R/predict.R`, `R/il_find_matches.R` | `tests/testthat/test-dependency-aware-scoring.R` |
| Save/load compatibility | `R/il_save.R` | `tests/testthat/test-il_save.R`, `test-il_attach.R` |

## Vignette Constraints

The vignettes show the R-facing contract we should optimize for before the
first public release.

- `vignettes/irelink.Rmd`, `deduplication.Rmd`, `record-linkage.Rmd`,
  `transactions.Rmd`, and `deduplicate-50k.Rmd` all teach the same resource
  pattern: create a DBI connection, build a model, run collected `predict()`,
  call `il_cleanup(model)`, then `DBI::dbDisconnect()`.
- `vignettes/advanced.Rmd` deliberately creates several models on one shared
  DuckDB connection (`model`, `model_phon`, `model_tr`) and cleans them one by
  one. That makes narrow, model-owned cleanup important: `il_cleanup(model)`
  should not delete tables needed by `model_phon` or `model_tr`.
- The same advanced vignette teaches `predict(collect = FALSE)` only for large
  data. Collected tibbles should remain the default R experience.
- Vignettes and README examples display `match_weight` as a diagnostic output
  and use `il_weights()` / waterfall plots to explain per-field contributions.
  That argues for keeping an evidence-only weight available and clearly named,
  even if a Splink-compatible total weight is also exposed.

Implication: add both `il_cleanup(model)` and `il_cleanup_all(con)`.
`il_cleanup(model)` should be safe for shared connections and vignettes with
multiple live models. `il_cleanup_all(con)` should be the explicit interactive
"clear every irelink table on this connection" escape hatch.

## Priority 1: Fix Prior Counting Semantics

Splink 5 improves blocking-count SQL and the prior-training workflow.
`irelink` prior estimation currently loops over blocking rules and sums
`count_blocked_pairs()` results. That double-counts pairs produced by multiple
rules.

Because the package is not public, make this a behavioral correction now rather
than preserving the old summed-rule behavior behind an option.

Relevant upstream context: Splink 5's prediction code now has an explicit
blocked-pairs materialization path (`table_management.py:94-164`) and a chunked
prediction path that always works from blocked pairs before scoring
(`inference.py:424-455`). That makes unique pair identity a first-class concern.

### Current Problem

`R/il_estimate_prior.R::il_estimate_prior()`:

```r
n_blocked <- n_blocked + count_blocked_pairs(...)
```

If two deterministic rules identify the same pair, that pair contributes twice.
This inflates the prior and then affects EM initialization and posterior match
probabilities.

### Concrete Change

Implementation tasks:

1. Add `count_unique_blocked_pairs(con, tbl_l, tbl_r, rules, link_type, dialect)`
   near `count_blocked_pairs()` in `R/utils-sql.R`.
2. Build a `UNION` over all rule-specific pair queries, then count unique
   `(l_unique_id, r_unique_id)` rows in the outer query.
3. Use `build_table_pairs()` for dedupe/link/link-and-dedupe so the same
   pair-eligibility rules apply as prediction.
4. Change `il_estimate_prior()` to use unique blocked-pair counting.
5. Validate `recall` strictly: finite scalar, `0 < recall <= 1`.
6. Keep current per-rule counts in `il_count_pairs()` because that diagnostic
   intentionally reports each rule's marginal and cumulative contribution.

Acceptance tests:

- Add an `il_estimate_prior()` test with two overlapping deterministic rules;
  prior should use unique pairs, not the sum of rule counts.
- Add tests for `recall <= 0`, `recall > 1`, `NA`, and `Inf`.
- Add dedupe, link, and link-and-dedupe prior tests.

## Priority 2: Explicit Table Lifecycle

Splink 5 removes implicit cache behavior and makes table management explicit.
`irelink` already has DBI-first table handling, but ownership is not explicit:
some tables are model-owned (`__il_data_l`, `__il_tf_*`), some are call-owned
(`__il_dependency_scores`, `__il_predicted_*`), and `il_cleanup()` drops every
table matching `^__il_`.

Since the package is pre-public, change table names and cleanup behavior
directly. Do not keep the broad cleanup behavior as the default.

Relevant upstream context: Splink exposes broad cleanup via
`delete_tables_created_by_splink_from_db()` (`database_api.py:368-373`,
`table_management.py:285-286`) and separately tracks registered tables in its
intermediate cache. The R version should split these into
`il_cleanup(model)` and `il_cleanup_all(con)`.

### Current Problem

`R/il_cleanup.R::il_cleanup()` drops all `^__il_` tables in the connection.
That is simple, but too broad if a user has multiple `irelink` models sharing a
connection. It can also delete diagnostic/lazy prediction tables still needed by
another object.

Temporary names also repeat in several places:

- `R/predict.R`: `__il_predicted_<id>`, `__il_dependency_scores`,
  `__il_row_index`;
- `R/utils-tf.R`: `__il_tf_<col>`;
- `R/il_profile.R`: `__il_profile_tmp`;
- `R/il_compare_records.R`: `__il_compare_records_tmp`;
- `R/utils-cc.R` and `R/il_cluster*.R`: connected-component scratch tables.

### Concrete Change

Introduce a lightweight model table registry, not a Splink-style backend class.

Implementation tasks:

1. Add internal helpers in `R/utils-register.R`:

   ```r
   il_table_name <- function(model, purpose, suffix = NULL)
   il_track_table <- function(model, tbl_name, owner = c("model", "call", "lazy"))
   il_untrack_table <- function(model, tbl_name)
   il_drop_tracked <- function(model, owner = NULL)
   ```

2. Give each `il_model` a session prefix when it is created or attached:

   ```r
   model$data$table_prefix <- paste0("__il_", Sys.getpid(), "_", next_counter())
   ```

   Avoid a new runtime dependency just to hash table names.

3. Update source table registration in `il_model()` / `register_data()` callers
   so model-owned tables use the prefix, for example
   `__il_<prefix>_data_l`, `__il_<prefix>_data_r`.
4. Update `compute_tf_tables()` in `R/utils-tf.R` to use
   `il_table_name(model, "tf", col)`.
5. Update `predict_lazy()` in `R/predict.R` to track prediction tables with
   owner `"lazy"`.
6. Update dependency-aware score lookup creation in
   `R/utils-dependency-aware.R::prepare_dependency_scored_query()` to use a
   generated call-owned table name rather than `__il_dependency_scores`.
7. Change `il_cleanup(model)` to drop only tracked tables by default. This is
   required by `vignettes/advanced.Rmd`, where multiple models share one
   connection.
8. Add an exported broad cleanup helper:

   ```r
   il_cleanup_all <- function(con)
   ```

   It should drop every table/view matching the package prefix on that
   connection. This is useful in interactive sessions and in failed vignette
   runs, but it must be opt-in and connection-scoped.
9. Update vignettes only if the semantics change visibly:
   - ordinary one-model vignettes keep `il_cleanup(model)`;
   - examples that intentionally want to clear a connection may use
     `il_cleanup_all(con)`;
   - `advanced.Rmd` should continue demonstrating per-model cleanup.

Acceptance tests:

- Add `tests/testthat/test-table-lifecycle.R`.
- Create two models on the same connection; call `il_cleanup(model_a)` and
  assert model B's source and TF tables still exist.
- Repeated `predict(model, collect = FALSE)` should create unique table names
  and cleanup should drop all lazy prediction tables owned by that model.
- Force an error during prediction with dependency-aware scoring and assert the
  call-owned score lookup table is dropped by `on.exit()`.
- Add an `il_cleanup_all(con)` test proving it removes tables for both models
  on a shared connection.

## Priority 3: Term Frequency at Prediction Time

Splink 5 joins term frequencies at `predict()` time. `irelink` mostly already
does this: `compute_tf_tables()` creates lookup tables, `build_gamma_query()`
adds TF scalar subqueries via `sql_tf_select_exprs()`, and `build_scored_query()`
adds `tf_adj_*` columns.

Because there are no public users depending on `__il_tf_<col>`, remove that
hard-coded convention rather than supporting it indefinitely.

Relevant upstream context: Splink registers TF lookup tables through
`register_term_frequency_lookup()` (`table_management.py:228-275`) and resolves
missing TF tables at prediction-time pipeline construction
(`term_frequencies.py:58-76`).

### Current Problem

The implementation relies on hard-coded table names in multiple places:

- `R/utils-tf.R::compute_tf_tables()` writes `__il_tf_<col>`;
- `R/utils-tf.R::sql_tf_select_exprs()` assumes `__il_tf_<col>`;
- `R/utils-tf.R::lookup_tf_r()` assumes `__il_tf_<col>`;
- `R/il_tf_chart.R` assumes `__il_tf_<col>`;
- `R/il_register_tf.R` writes `__il_tf_<col>`.

This conflicts with model-specific table prefixes from Priority 2 unless the TF
functions read table names from `model$data$tf_tables`.

### Concrete Change

Implementation tasks:

1. Change `sql_tf_select_exprs(tf_cols)` to accept `tf_tables`:

   ```r
   sql_tf_select_exprs <- function(tf_cols, tf_tables)
   ```

   Do not keep a silent hard-coded fallback in new code.

2. In `build_gamma_query()`, pass `model$data$tf_tables`.
3. Change `lookup_tf_r()` and `il_tf_chart()` to resolve `tf_tbl` from
   `model$data$tf_tables[[col]]`.
4. Change `il_register_tf()` to allocate a model-prefixed table name and update
   `model$data$tf_tables[[col]]`.
5. Make `il_register_tf()` return the updated model, not invisibly. Losing the
   returned model should be a normal R user error, not something the package
   tries to patch around.
6. On `il_attach()`, recompute TF tables for comparisons with
   `term_frequency = TRUE` unless explicitly registered TF data is supplied.

Acceptance tests:

- Extend `tests/testthat/test-term-frequency.R`: two models on the same
  connection with TF on the same column should not overwrite each other's TF
  tables.
- Extend `tests/testthat/test-il_attach.R`: a saved/loaded/attached model with
  TF enabled predicts with the same `match_weight` as the original.
- Extend `tests/testthat/test-il_tf_chart.R`: chart lookup uses
  `model$data$tf_tables`, not hard-coded table names.

## Priority 4: Chunked `il_estimate_u()`

Splink 5 adds chunking and early stopping to
`estimate_u_using_random_sampling()`. `irelink` currently does one aggregate
query through `get_random_pairs_with_gammas(model, max_pairs)` and then computes
level frequencies in `il_estimate_u()`.

Relevant upstream context: the public training API exposes
`min_count_per_level` and `num_chunks` (`training.py:160-166`, `:192-197`,
`:217-223`). The implementation samples records first (`estimate_u.py:406-427`)
and then chunks only the RHS while accumulating counts and stopping early
(`estimate_u.py:448-523`).

### Current Problem

`R/utils-em.R::get_random_pairs_with_gammas()` builds all table-pair SQL,
applies `LIMIT max_pairs`, groups gamma patterns, and returns one aggregated
table. For DuckDB/PostgreSQL this is compact on the R side, but it still asks
the database planner to consider one large cross product. For SQLite fallback,
`get_all_pairs()` collects pair rows into R before gamma aggregation.

`R/il_estimate_u.R::il_estimate_u()` has only `max_pairs`; it cannot stop once
all comparison levels have enough support.

### Concrete Change

Add arguments:

```r
il_estimate_u <- function(
  model,
  max_pairs = 1e6,
  min_count_per_level = NULL,
  chunk_size = NULL,
  seed = NULL
)
```

Implementation tasks:

1. Keep old behavior when `min_count_per_level` and `chunk_size` are both
   `NULL`.
2. Add a new internal helper in `R/utils-em.R`, for example
   `get_random_pair_gamma_counts_chunked(model, max_pairs, chunk_size, seed)`.
3. Return the same shape as `get_random_pairs_with_gammas()`:
   `list(counts = <gamma pattern counts>, n_pairs = <integer>)`.
4. Accumulate counts by gamma pattern across chunks, then let
   `il_estimate_u()` convert pattern counts to per-comparison u values as it
   does now.
5. Stop early when every `(comparison, gamma_level)` count is at least
   `min_count_per_level`.
6. Store metadata in the fitted model, e.g.
   `model$params$u_estimation <- list(n_pairs_sampled = ..., stopped_early = ..., min_count_per_level = ..., chunk_size = ...)`.

Suggested SQL shape for DuckDB/PostgreSQL:

- Add a deterministic row number or random key over the pair stream.
- Sample ranges with `WHERE __rn > offset AND __rn <= offset + chunk_size`, or
  use seeded random ordering if we decide reproducibility is worth the planner
  cost.
- Reuse `build_table_pairs()` and `sql_gamma_case()` from `R/utils-sql.R`.

SQLite fallback can remain simpler:

- call `get_all_pairs(model, max_pairs = chunk_size)` repeatedly only if the
  source can be chunked deterministically;
- otherwise keep old behavior and document that chunking is SQL-backend-only.

Acceptance tests:

- In `tests/testthat/test-il_estimate.R`, add a case where
  `min_count_per_level = 1` stops before `max_pairs` and sets
  `model$params$u_estimation$stopped_early` to `TRUE`.
- Add a case proving chunked and unchunked output agree on a small deterministic
  dataset when `chunk_size >= max_pairs`.
- Add a link-mode test using two input tables, because
  `build_table_pairs()` has different dedupe/link/link-and-dedupe branches.
- Add a test that all gamma levels for a multi-level comparison are represented
  in the output with a u floor when a level is unobserved.

## Priority 5: Blocked-Pairs Materialization

Splink 5 always materializes blocked pairs for prediction and exposes
`register_blocked_pairs_for_predict`. `irelink` currently generates blocked
pairs inside `build_gamma_query()` or collects them through
`get_blocked_pairs()` for fallback paths. There is no reusable blocked-pairs
table.

Relevant upstream context: registered blocked pairs require explicit chunk keys
and are stored under a blocked-pairs cache key (`table_management.py:94-164`).
Splink's `predict()` rejects the registered-blocked-pairs workflow and tells
users to call `predict_chunk()` (`inference.py:274-288`), while `predict_chunk()`
uses `_get_or_compute_blocked_pairs_for_predict_chunk()` before scoring
(`inference.py:424-455`).

### Current Problem

The same blocking work can be repeated by:

- `predict()` / `predict_lazy()` through `build_scored_query()`;
- `il_estimate_em()` through `get_pairs_with_gamma_counts()`;
- `il_comparison_vectors()` through `build_gamma_query()`;
- blocking diagnostics through `il_count_pairs()` and `il_largest_blocks()`.

This is acceptable for small examples, but Splink 5's change suggests large
workflows benefit from an explicit materialization boundary.

### Concrete Change

Add an internal blocked-pairs table helper first. Only export it later if a real
user workflow needs it.

Implementation tasks:

1. Add `register_blocked_pairs(model, blocking_rules, purpose = "predict",
   overwrite = FALSE)` in `R/utils-em.R` or a new `R/utils-blocked-pairs.R`.
2. Use `build_gamma_query(..., deduplicate = TRUE)` or split it into two layers:
   one query that produces unique blocked pair IDs and another that computes
   gamma columns. The second option is better if prediction, EM, and diagnostics
   all share the pair table.
3. Table columns should start with `l_unique_id`, `r_unique_id`, and, if needed,
   source dataset columns. Do not store full original fields unless a fallback
   R path needs them.
4. Add `match_key` only if needed for diagnostics; prediction should not depend
   on it.
5. Update `build_gamma_query()` to optionally accept `blocked_pairs_tbl`.
6. Update `predict_lazy()` and `build_scored_query()` to use the materialized
   blocked-pairs table when supplied.

Acceptance tests:

- In `tests/testthat/test-blocked-pairs.R`, assert overlapping blocking rules
  produce one unique `(l_unique_id, r_unique_id)` pair.
- Test dedupe, link, and link-and-dedupe separately.
- Test weird identifiers: `unique_id` as character, names requiring quoting,
  and raw SQL `.where` rules.
- Compare `predict(model)` with and without a registered blocked-pairs table on
  the same model.

## Priority 6: Match-Weight and Prior Semantics

Splink 5 renames/moves internals from Bayes factors to match weights.
`irelink` already exposes `match_weight`, but it deliberately excludes the
prior from the output `match_weight`. Splink includes the prior in its
match-weight column. `match_probability` should still agree when parameters and
candidate pairs agree.

Relevant upstream context: Splink sums per-comparison match-weight terms,
combines them with the prior, and exposes the combined expression as
`match_weight` (`predict.py:89-111`). `_combine_prior_and_mws()` adds
`prob_to_match_weight(prior)` to the terms and computes probability from the
combined weight (`predict.py:203-229`). Splink 5 also ignores old
`bayes_factor_column_prefix` settings in favor of `match_weight_column_prefix`
(`settings_creator.py:148-154`).

This is a place where the old behavior may be preferable for R users.
Evidence-only `match_weight = sum(log2(m/u))` is easier to explain in
`il_weights()`, waterfall charts, and model diagnostics because it separates the
field evidence from the global base rate. Splink's prior-inclusive value is more
portable to Splink thresholds, but it mixes two concepts.

### Current Problem

This difference is easy to lose during maintenance. It affects
`threshold_match_weight` portability and any Splink JSON import/export that
expects prior-inclusive match weights.

Relevant code:

- `R/utils-sql.R::sql_weight_case()` computes per-comparison log2(m/u).
- `R/utils-sql.R::build_scored_query()` sums evidence weights and applies prior
  in the probability transform.
- `R/utils-scoring.R::score_gamma_matrix()` and `weight_to_probability()` do the
  R-side equivalent.
- `R/il_waterfall.R` decomposes the evidence weight plus prior contribution.

### Concrete Change

Do not blindly align the core diagnostic column with Splink. Decide explicitly
between two viable designs before release:

- **R-first design, recommended:** keep `match_weight` evidence-only, add
  `total_match_weight` or `posterior_weight` if a prior-inclusive log2 odds
  column is useful, and document that Splink `threshold_match_weight` values are
  not portable without adding the prior.
- **Splink-first design:** make `match_weight` prior-inclusive and rename the
  old diagnostic value to `evidence_weight`.

Given the current vignettes, the R-first design is probably better.

Implementation tasks:

1. Add small internal helpers in `R/utils-scoring.R`:

   ```r
   prior_match_weight <- function(prior) log2(prior / (1 - prior))
   evidence_to_match_weight <- function(evidence_weight, prior) {
     evidence_weight + prior_match_weight(prior)
   }
   ```

2. If choosing the R-first design, leave current prediction semantics in place:
   `match_weight` remains evidence-only and `match_probability` applies the
   prior. Optionally add `total_match_weight` with the prior included.
3. If choosing the Splink-first design, update both
   `R/utils-sql.R::build_scored_query()` and the R fallback in `R/predict.R` so
   `match_weight` is prior-inclusive and the old value is `evidence_weight`.
4. In either design, make `threshold_match_weight` unambiguous in documentation
   and tests. Under the R-first design it filters evidence-only weight. Under
   the Splink-first design it filters prior-inclusive weight.
5. Keep `R/il_waterfall.R` decomposed into per-comparison evidence plus prior as
   a separate contribution. Do not force prior-inclusive weights into a
   per-field diagnostic.
6. Search and update misleading internal wording around Bayes factors:
   `rg "bf_|bayes_factor|Bayes factor|bf" R tests inst`.
7. Keep saved model compatibility in `R/il_save.R`: if Splink 5 JSON uses
   `match_weight_column_prefix`, parse it as metadata but do not let it silently
   change `irelink` scoring semantics.

Acceptance tests:

- Add tests in `tests/testthat/test-predict.R` proving the chosen semantics:
  if R-first, `match_probability == plogis(log(prior/(1-prior)) + match_weight * log(2))`;
  if Splink-first, `match_probability == 2^match_weight / (1 + 2^match_weight)`.
- Add a test showing exactly which weight `threshold_match_weight` filters.
- Add `il_waterfall()` tests showing per-comparison contributions sum to the
  evidence component and prior is separate.
- Add a JSON fixture in `tests/testthat/test-il_save.R` if Splink 5 model JSON
  changes field names around match-weight prefixes.

## Lower-Priority Splink 5 Items

### Query SQL Returning Lazy Tables

Splink changed `query_sql()` to return `SplinkDataFrame` by default. The
`irelink` equivalent is not a new public wrapper; use `DBI::dbGetQuery()` for
collected results and `collect = FALSE` outputs for package-owned lazy results.

Concrete task: make evaluation functions accept `il_compared_lazy` wherever
reasonable. Existing touchpoints include `R/utils-evaluation.R`,
`R/il_confusion_matrix.R`, `R/il_cluster_confusion_matrix.R`, and
`R/il_unlinkables.R`.

### SQL Profiling

Splink 5 can profile SQL executed in DuckDB/Spark. Useful, but not required for
feature parity.

Concrete task: add an internal wrapper:

```r
il_db_execute <- function(con, sql, step = NULL, profile = NULL)
il_db_get_query <- function(con, sql, step = NULL, profile = NULL)
```

Use it first in `predict_lazy()`, `build_scored_query()` callers,
`il_estimate_u()`, and `il_estimate_prior()`. Store timings in
`model$params$sql_profile` only when profiling is enabled.

### Charts and Structured Chart Records

Do not port `SplinkChart`. Instead, verify that data exists for each diagnostic.

Concrete task: compare Splink 5 chart data against these R surfaces:
`il_weights()`, `il_parameters()`, `il_training_history()`, `il_tf_chart()`,
`il_waterfall()`, `il_profile()`, `il_completeness()`, and `il_unlinkables()`.
Only add missing tidy data columns.

### Removed Salting and Athena

No implementation work. Update parity docs to say Splink 5 removed these and
they are not `irelink` gaps.

### Dropping pandas/numpy

No direct implementation work. It supports the current `irelink` direction:
tibbles for collected results, DBI tables for lazy/large results.

### JSON Schema Removal

Concrete task: stop relying on upstream schema files if any are still used.
`R/il_save.R` should validate by known fields and tolerate unknown Splink 5
metadata. Add one Splink 5 JSON fixture once the format stabilizes.

## Implementation Order

1. Fix unique blocked-pair counting in `il_estimate_prior()`. It is a
   correctness improvement and small enough to land first.
2. Add a tracked table registry and narrow `il_cleanup()`. This should happen
   before touching TF and prediction table names.
3. Add `il_cleanup_all(con)` as the explicit broad cleanup escape hatch and
   update cleanup tests around the vignette patterns.
4. Make TF table lookup model-specific and remove hard-coded `__il_tf_<col>`
   assumptions.
5. Decide and document match-weight semantics. Prefer the R-first evidence-only
   `match_weight` unless strict Splink threshold portability becomes a release
   goal.
6. Add chunked/early-stop `il_estimate_u()`.
7. Add optional blocked-pairs materialization and wire it into prediction.
8. Add profiling wrappers only after the query boundaries are stable.

## Definition of Done for Splink 5 Parity

The migration should be considered useful only when these concrete checks pass:

- `il_estimate_prior()` counts unique deterministic pairs across overlapping
  rules.
- `il_estimate_u()` can stop on per-level support before exhausting `max_pairs`.
- Two models with TF comparisons can share one DBI connection without table-name
  collisions.
- `predict(collect = FALSE)` tables are tracked and cleaned up per model.
- `il_cleanup(model)` is narrow, and `il_cleanup_all(con)` clears all package
  tables on a connection when explicitly requested.
- `match_weight` semantics are explicitly chosen for the R API and covered by
  tests. If kept evidence-only, any prior-inclusive compatibility value has a
  distinct name.
- Prediction with and without materialized blocked pairs returns identical
  pairs, weights, and probabilities.
- Custom priors and dependency-aware EM tests still pass after scoring/table
  lifecycle changes.
