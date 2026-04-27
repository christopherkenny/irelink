# Splink 5 Maintenance Investigation

This note summarizes the main Splink 5 changes that matter for keeping
`irelink` close to feature parity with Splink, while preserving the parts where
the R package has intentionally diverged.

Sources checked:

- Upstream Splink 5 development changelog:
  <https://raw.githubusercontent.com/moj-analytical-services/splink/splink_5_dev/CHANGELOG.md>
- Release-summary pull request list from the maintenance prompt.
- Local `../splink` checkout for nearby 4.x context. The local checkout was on
  `master`, so the `splink_5_dev` changelog is the source of truth for the 5.0
  items below.

## Executive Summary

Splink 5 is mostly a performance, backend, and internal-state-management
release rather than a new statistical-model release. The changes that matter
most for `irelink` are:

1. explicit lifecycle management for intermediate database tables;
2. chunked execution for u-estimation, blocking, and prediction;
3. match-weight-first internals instead of Bayes-factor-first internals;
4. term-frequency tables joined at prediction time rather than precomputed;
5. faster `u` and prior-training workflows;
6. removal of salting and Athena;
7. movement away from pandas and toward backend-owned table objects;
8. chart/output APIs moving toward structured records.

For `irelink`, the highest-value parity work is not to copy Splink's Python
backend architecture. We should instead map the Splink 5 ideas onto the current
DBI design: stable temporary-table registration, chunkable SQL workflows,
backend-neutral output tables, and parity tests for scoring, u-estimation,
blocking counts, and prediction.

## Existing Divergence to Preserve

`irelink` is already not a literal port, and the Splink 5 migration should not
erase those differences.

### Interactive Graphs

Splink continues to invest in interactive visualisation and dashboard outputs.
`irelink` should keep treating these as data products plus ordinary R plotting
surfaces. The existing stance remains sound:

- return tidy data for charts and diagnostics;
- support `autoplot()` where a static ggplot is useful;
- leave richer dashboards to Shiny, DT, Quarto, or downstream packages.

Splink 5's `SplinkChart` and structured chart records are worth watching, but
they do not require a direct port unless they expose new diagnostic data that
`irelink` cannot currently produce.

### DBI Instead of Custom Database Backends

Splink 5 continues to move more behavior into its database API and
`SplinkDataFrame` abstractions. `irelink` should not recreate those custom
Python backends. The R equivalent should remain:

- DBI connections as the backend contract;
- dialect detection for SQL generation;
- explicit table registration and cleanup helpers;
- lazy prediction objects that reference DBI tables where needed.

When Splink 5 adds backend-management behavior, the maintenance question should
be "what DBI lifecycle or SQL generation behavior does this imply?", not "what
Python class do we need to mirror?"

### Additional Statistical Features

`irelink` has moved beyond Splink in some statistical areas, notably custom
priors and dependency-aware EM. These should be treated as first-class package
features during parity work:

- independent EM should continue to support regularizing priors and fixed
  matched-class constraints;
- dependency-aware EM should continue to score joint comparison patterns rather
  than force a fieldwise decomposition;
- any Splink 5 scoring or training changes must be checked against both
  independent and dependency-aware estimators.

## Major Splink 5 Changes and `irelink` Impact

### 1. Explicit Cache and Table Management

Splink 5 removes implicit caching and introduces explicit table-management
functions. It also removes the `use_cache` parameter and the
`materialise_blocked_pairs` prediction argument. Blocked pairs are now always
materialised in Splink 5.

Impact for `irelink`:

- `irelink` already uses DBI tables and cleanup helpers rather than Splink's
  implicit cache, but table ownership is still spread across prediction,
  training, term-frequency, and lazy clustering paths.
- The parity task is to make intermediate table lifecycle explicit and
  inspectable: registered data tables, term-frequency tables, blocked-pair
  tables, scored prediction tables, dependency-aware pattern score lookups, and
  clustering scratch tables.
- Public API does not need to expose every internal table, but users should have
  a reliable cleanup function and predictable temporary names.

Recommended work:

- Audit every `dbWriteTable`, `CREATE TABLE`, `CREATE TEMP TABLE`, and
  `drop_registered()` call.
- Create one internal table registry convention for model-owned intermediate
  tables.
- Decide which tables are ephemeral per call and which are model/session-owned.
- Add tests that repeated prediction/training calls do not reuse stale tables
  or leave conflicting names behind.

### 2. Chunking for Large Datasets

Splink 5 adds chunking for very large datasets in blocking and prediction, and
uses chunking in `estimate_u_using_random_sampling()`. The changelog also notes
that u-estimation can stop early once each comparison level has enough observed
u counts.

Impact for `irelink`:

- `il_estimate_u()` currently samples random pairs and aggregates gamma counts,
  but it does not expose `min_count_per_level` or an early-stop strategy.
- Prediction is SQL-first for DuckDB/PostgreSQL and has lazy output support, but
  the package does not yet have a generic chunked execution plan for backends or
  operations that cannot handle one very large query comfortably.
- This is the largest practical feature-parity gap for large data.

Recommended work:

- Add `min_count_per_level` and possibly `batch_size` or `chunk_size` to
  `il_estimate_u()`.
- Implement chunked random-pair sampling by repeatedly aggregating counts and
  stopping when all comparison levels have sufficient support or `max_pairs` is
  exhausted.
- For prediction, investigate chunking by blocking rule, source dataset, or
  deterministic slices of the left table. Preserve global deduplication of
  candidate pairs across blocking rules.
- Add benchmarks that compare current and chunked paths on wide comparison
  specs and skewed blocking rules.

### 3. Match-Weight-First Internals

Splink 5 changes internal probabilistic calculations to use match weights
(log-odds/log2 weights) instead of Bayes factors for numerical stability. It
deprecates `bayes_factor_column_prefix` in favor of
`match_weight_column_prefix`.

Impact for `irelink`:

- `irelink` already exposes `match_weight` and computes much of scoring in log
  space, so this is mostly confirmatory rather than disruptive.
- Prior semantics still differ: existing notes record that `irelink` treats
  `match_weight` as evidence weight excluding the prior, while Splink includes
  the prior in the match-weight column. This should remain documented because it
  affects `threshold_match_weight` portability.
- Any remaining internal names, docs, tests, or saved JSON fields using `bf`,
  `bayes_factor`, or Bayes-factor language should be reviewed.

Recommended work:

- Search for `bf`, `bayes_factor`, and `Bayes factor` across R, tests, docs,
  and saved-model code.
- Keep `match_weight` as the user-facing name.
- Add a migration note that Splink's `match_weight` thresholds are not directly
  portable if the prior is included upstream but excluded in `irelink`.
- Ensure infinite or near-zero probability cases are guarded in SQL and R.

### 4. Term Frequencies at Prediction Time

Splink 5 joins term-frequency data at prediction time rather than precomputing
all term-frequency-adjusted inputs. This is likely a performance and lifecycle
cleanup change.

Impact for `irelink`:

- `irelink` already has explicit term-frequency registration and prediction-time
  adjustment logic, including SQL-backed paths.
- The main parity risk is whether term-frequency tables are refreshed,
  registered, and cleaned consistently across `predict()`, lazy prediction,
  `il_find_matches()`, save/load, and `il_attach()`.

Recommended work:

- Compare `irelink` term-frequency behavior to Splink 5 on a small model with
  one TF-adjusted comparison.
- Confirm that prediction-time joins work after save/load and after attaching a
  model to a new DBI connection.
- Add lifecycle tests for missing, stale, and newly registered TF tables.

### 5. Faster u and Prior Training

The Splink 5 changelog mentions optimized `train_u`, faster
`estimate_probability_two_random_records_match`, and an alternative improved
u-training implementation.

Impact for `irelink`:

- `il_estimate_u()` is the obvious target for performance parity.
- `il_estimate_prior()` should be checked against Splink 5's updated blocking
  count SQL and faster prior-training workflow.
- Because `irelink` has custom priors and dependency-aware EM, training changes
  need regression tests that cover both ordinary Splink parity and R-specific
  statistical extensions.

Recommended work:

- Profile `il_estimate_u()` and `il_estimate_prior()` on the benchmark scripts
  already in `inst/benchmarks`.
- Port the idea of early stopping by per-level count, not necessarily the exact
  Python implementation.
- Add tests for deterministic seeded u-estimation, custom unique IDs, and link
  vs dedupe vs link-and-dedupe sampling behavior.

### 6. Blocking Workflow API and SQL Improvements

Splink 5 adds `register_blocked_pairs_for_predict`, finalizes the computed
blocked-pairs workflow API, improves blocking-count SQL, ports several blocking
optimizations, and fixes match-key/unique-id quoting issues.

Impact for `irelink`:

- `irelink` has `il_count_pairs()`, `il_largest_blocks()`, SQL-first
  prediction, and blocking-rule support, but it does not have a public "register
  blocked pairs for prediction" function.
- The useful parity behavior is explicit reuse of a blocked-pairs table where
  this avoids recomputing expensive candidate generation.
- Quoting and aliasing remain high-risk areas because `irelink` accepts R column
  expressions, raw SQL `.where` clauses, and multiple DBI dialects.

Recommended work:

- Consider an internal `register_blocked_pairs()` helper used by prediction,
  EM, and blocking diagnostics.
- Preserve the public R API unless there is a clear user workflow for reusing
  blocked pairs.
- Add tests for nonstandard unique ID names, quoted identifiers, source
  datasets, overlapping blocking rules, and raw SQL blocking conditions.

### 7. Removal of Salting and Athena

Splink 5 removes salting and drops Athena support.

Impact for `irelink`:

- These removals align with existing `irelink` scope. Salting was already
  considered a Spark/Athena-style distributed-backend feature rather than an R
  DBI requirement.
- No feature gap should be opened for either item.

Recommended work:

- Update feature-parity docs to mark salting and Athena as removed upstream or
  out of scope.
- Avoid adding salting solely for historical Splink 4 parity.

### 8. Dropping pandas/numpy as Required Dependencies

Splink 5 no longer requires pandas or numpy and moves toward
`SplinkDataFrame`, Arrow, DuckDB tables, and backend-native table objects.

Impact for `irelink`:

- This aligns with the existing R approach: return tibbles when collecting, use
  DBI tables for large/lazy work, and avoid Python-style dataframe adapters.
- It reinforces that large outputs should remain in the database until the user
  asks to collect.

Recommended work:

- Continue treating `collect = FALSE` as the large-data path.
- Make sure diagnostics and evaluation functions can consume lazy prediction
  outputs where possible.
- Avoid adding dependencies that force large result materialization into R.

### 9. Query SQL Output and SQL Profiling

Splink 5 changes `linker.misc.query_sql()` to return a `SplinkDataFrame` by
default and adds SQL profiling for DuckDB and Spark pipelines.

Impact for `irelink`:

- The equivalent of `query_sql()` is ordinary `DBI::dbGetQuery()` for collected
  results, plus lazy DBI tables where the package owns the query.
- SQL profiling could be useful in `irelink`, especially for benchmark and
  maintenance work.

Recommended work:

- Do not add a wrapper just to mirror `query_sql()`.
- Consider an optional `profile = TRUE` or internal timing hook around generated
  SQL pipelines for `predict()`, `il_estimate_u()`, `il_estimate_prior()`, and
  clustering.
- Store profiling output as a small tibble with step name, SQL preview, elapsed
  time, and row count when available.

### 10. Charts and Structured Chart Records

Splink 5 introduces `SplinkChart` and structured chart records, and ports TF
adjustment charts away from pandas.

Impact for `irelink`:

- `irelink` should maintain tidy diagnostic tables and ggplot/autoplot outputs
  instead of copying Splink's chart object model.
- The parity risk is missing diagnostic data, not missing chart classes.

Recommended work:

- Compare Splink 5 chart inputs against `il_parameters()`, `il_weights()`,
  `il_training_history()`, `il_tf_chart()`, `il_waterfall()`, `il_profile()`,
  `il_completeness()`, and `il_unlinkables()`.
- Add tidy outputs only where Splink exposes useful new diagnostics.

### 11. JSON Schema Removal

Splink 5 notes that the JSON schema no longer exists.

Impact for `irelink`:

- `irelink` has `il_save()`, `il_load()`, and support for loading valid Splink
  JSON models. If Splink removes or changes schema validation, compatibility
  should be tested against concrete saved model examples rather than schema
  files.

Recommended work:

- Keep a small fixture set of Splink 4 and Splink 5 model JSON files.
- Validate by round-tripping into `irelink`, attaching data, and predicting.
- Treat unknown JSON fields as ignorable unless they affect scoring, blocking,
  comparisons, term frequencies, or link type.

## Suggested Maintenance Plan

### Phase 1: Parity Triage

- Update `18-feature-parity.md` or add a Splink 5 appendix with the changes
  above.
- Mark each Splink 5 item as `port`, `already covered`, `intentional
  divergence`, or `out of scope`.
- Add a small fixture checklist covering dedupe, link, link-and-dedupe,
  term-frequency, custom IDs, source datasets, and dependency-aware scoring.

### Phase 2: Table Lifecycle Cleanup

- Centralize internal table registration and cleanup.
- Make repeated prediction/training calls deterministic with respect to
  temporary table names.
- Add tests for stale table avoidance and cleanup after errors.

### Phase 3: Chunked u-Estimation

- Extend `il_estimate_u()` with per-level minimum support and chunked sampling.
- Keep the old behavior as the default if the new controls are not set, or pick
  conservative defaults that preserve current small-data behavior.
- Benchmark on synthetic skewed data and existing package benchmarks.

### Phase 4: Blocking and Prediction Reuse

- Introduce an internal blocked-pairs table workflow.
- Decide whether users need a public precompute/reuse function or whether this
  remains an internal optimization.
- Ensure overlapping blocking rules still deduplicate candidate pairs exactly
  once.

### Phase 5: Scoring and Terminology Audit

- Remove stale Bayes-factor terminology where it implies internal linear-domain
  computation.
- Keep clear documentation of `irelink`'s evidence-only match-weight convention.
- Add cross-package examples showing probability equivalence and threshold
  differences.

### Phase 6: Diagnostics and Profiling

- Add optional SQL timing/profiling for generated pipelines.
- Compare Splink 5 structured chart records to existing tidy diagnostic outputs.
- Fill any missing diagnostic data gaps without adding interactive dashboard
  dependencies.

## Compatibility Policy

Because R packages have CRAN-facing stability expectations that Python packages
often do not, `irelink` should not chase every Splink 5 breaking API change at
the user interface level. The package should instead maintain:

- statistical parity for core Fellegi-Sunter scoring, EM, u-estimation, prior
  estimation, term frequencies, prediction, clustering, and evaluation;
- performance parity where Splink 5 changes materially improve large-data
  workflows;
- documented divergence where R idioms or existing package extensions are
  preferable;
- model-file tolerance across Splink 4 and Splink 5 where practical.

The guiding rule is: port behavior and guarantees, not Python object structure.

## Proposed Priority Ranking

| Priority | Area | Reason |
|---|---|---|
| 1 | Chunked `il_estimate_u()` with early stop | Largest likely performance gap and directly called in normal workflows |
| 2 | Explicit table lifecycle registry | Aligns with Splink 5 cache removal and reduces stale-table bugs |
| 3 | Blocking/prediction materialization workflow | Enables reuse and better large-data scaling |
| 4 | Term-frequency lifecycle tests | Important correctness risk around prediction-time joins |
| 5 | Match-weight/Bayes-factor terminology audit | Prevents confusion as Splink 5 renames internals |
| 6 | SQL profiling hooks | Useful for maintenance and benchmarks, not core parity |
| 7 | Structured chart-data comparison | Lower priority because interactive graphs are out of scope |
| 8 | Athena/salting removals | No action beyond documentation |

## Bottom Line

Splink 5's main lesson for `irelink` is operational: make intermediate data
explicit, make large workflows chunkable, and keep scoring in numerically stable
match-weight space. The package already matches or intentionally diverges from
several Splink 5 directions: DBI replaces custom database APIs, tidy outputs
replace interactive chart objects, salting/Athena are out of scope, and
`irelink` has additional statistical features that should remain protected.

The next concrete implementation target should be chunked `il_estimate_u()`
plus an explicit internal table lifecycle audit. Those two changes would capture
most of the practical value of the Splink 5 migration while staying idiomatic to
R and stable for existing users.
