# irelink 0.0.1

Initial development release, translating Python's [splink](https://github.com/moj-analytical-services/splink) probabilistic record linkage engine into idiomatic R.

## Core pipeline

- `il_spec()`, `il_compare()`, and `il_block_on()` define the linkage model declaratively: which fields to compare, how to compare them, and which blocking rules to apply.
- `il_model()` binds a spec to one or two datasets and a DBI connection for `dedupe`, `link`, or `link_and_dedupe`, and accepts in-memory data frames, `dbplyr::tbl_lazy` references, or existing table-name strings.
- `predict()` scores all candidate pairs above a match-probability threshold (or an evidence-only match-weight threshold via `threshold_match_weight`).
- `il_cluster()` resolves scored pairs into entity clusters via connected components (using igraph) or single-best-link (with `source_dataset` for cross-source filtering).

## Comparison library

- String similarity: `cl_exact()`, `cl_levenshtein()`, `cl_damerau_levenshtein()`, `cl_jaro()`, `cl_jaro_winkler()`, `cl_jaccard()`, `cl_cosine()`.
- Numeric and distance: `cl_numeric_diff()`, `cl_pct_diff()`, `cl_geo_distance()`.
- Temporal: `cl_date_diff()` for date proximity with `days()`, `months()`, and `years()` helpers, and `cl_time_diff()` for sub-day precision with `seconds()`, `minutes()`, and `hours()` helpers.
- Collections: `cl_array_intersect()`, `cl_array_subset()`, `cl_array_min_distance()`.
- Domain-specific: `cl_name()`, `cl_first_last_name()` / `cl_forename_surname()` (both accept a companion column for the surname and handle first/last swap detection), `cl_dob()`, `cl_email()`, `cl_domain()`, `cl_soundex()`, `cl_zip_code()` (exact, 5-digit ZIP+4, and 3-digit Sectional Center Facility prefix levels), `cl_postcode()`.
- Composition: `cl_levels()`, `cl_and()`, `cl_or()`, `cl_not()`, `cl_null()`, `cl_else()`, `cl_literal()`, `cl_custom()`, `cl_columns_reversed()`.
- All applicable comparators accept `term_frequency = TRUE` for Fellegi-Sunter term-frequency adjustments.

## Column transforms

- `il_transform()` composes multiple R functions into a chainable transform with SQL-side nesting (e.g. `TRIM(LOWER(col))`).
- Column transform factories for SQL-side column expressions: `il_substr()`, `il_regex_extract()`, `il_nullif()`, `il_cast_to_string()`, `il_try_parse_date()`, `il_array_element()`.
- Built-in transforms auto-translated to SQL: `tolower`, `toupper`, `trimws`.
- Phonetic transforms: `il_soundex()`, `il_metaphone()`, `il_dmetaphone()` (usable as R functions and SQL macros).

## Blocking

- `il_block_on()` and `block_on()` for equality-based and custom SQL blocking rules, with per-column transform support via formula syntax (`col ~ transform`, e.g. `first_name ~ il_substr(1, 3)`) or a named-list `.transform` for programmatic construction.
- `.explode` parameter for array-valued blocking columns (generates `UNNEST` subqueries for DuckDB).
- `il_count_pairs()` estimates candidate-pair counts, including cumulative totals and percent-of-cartesian summaries across rule combinations.
- `il_suggest_blocking()` ranks candidate blocking rules by pair-reduction, coverage, and balanced score.
- `il_find_blocking_below()` finds blocking rule combinations below a pair count ceiling.
- `block_from_labels()` measures per-column recall from labeled pairs.
- `il_largest_blocks()` identifies the blocking keys that generate the most records and pairs, respecting blocking transforms.

## Training

- `il_estimate_u()` estimates non-match probabilities by sampling random pairs, with optional chunked estimation through `chunk_size` and early stopping through `min_count_per_level`.
- `il_estimate_em()` runs the Fellegi-Sunter EM algorithm with configurable `max_iterations`, `convergence`, `fix_u`, `fix_m`, `fix_prior`, `derive_prior`, `estimate_without_tf`, and `estimator_mode` parameters.
- `estimator_mode = "dependency-aware"` fits log-linear matched and unmatched comparison-pattern distributions over aggregated gamma counts, preserving missing comparison states as explicit pattern levels.
- `il_estimate_prior()` sets the prior match probability from deterministic matching rules, counting unique blocked pairs across overlapping rules.
- `il_prior_prevalence()` and `il_prior_m()` add regularizing custom priors for EM, `il_constrain_m()` adds explicit fixed matched-class constraints, and `il_priors()` / `il_constraints()` expose the stored metadata.
- `il_estimate_m_from_labels()` and `il_estimate_m_from_column()` initialize parameters from ground-truth labels.

## Prediction

- `predict()` supports both `threshold` (match probability) and `threshold_match_weight` (evidence-only log2 Bayes factor) filtering.
- Prediction output includes evidence-only `match_weight`, prior-inclusive `total_match_weight`, and posterior `match_probability`.
- `predict(type = "weights")` returns match weights on the log2 Bayes-factor scale, and `greedy = TRUE` adds deterministic one-to-one post-processing for `link` models.
- `include_fields = TRUE` joins all source columns into the scored output.
- `collect = FALSE` returns an `il_compared_lazy` object backed by a model-scoped in-database table.
- `il_score_missing_edges()` enumerates and scores unscored within-cluster pairs.
- `il_score_patterns()` scores compatible comparison-pattern tables, including dependency-aware pattern tables larger than the table used for fitting.
- `il_deterministic_link()` performs single-table exact-match deduplication without training.
- `il_find_matches()` scores a set of probe records against existing data.
- `profile_sql = TRUE` on `predict()` attaches lightweight SQL timing metadata to collected predictions or lazy prediction objects.

## Diagnostics and evaluation

- `il_parameters()` and `il_weights()` expose the learned m/u parameters.
- `il_waterfall()` decomposes a pair's match weight into per-comparison contributions.
- `il_training_history()` tracks parameter convergence across EM iterations.
- `il_completeness()` and `il_profile()` summarize data quality, and `il_profile()` accepts raw SQL expressions as column definitions (e.g., `"city || left(first_name, 1)"`).
- `il_unlinkables()` identifies records that cannot be linked under any blocking rule.
- `il_accuracy()`, `il_precision_recall()`, and `il_roc()` evaluate performance against labeled data.
- `il_errors()` surfaces false positives and false negatives.
- `il_graph_metrics()` computes node degree, node centrality, cluster density, cluster centralization, and bridge detection.
- `il_comparison_vectors()` returns the gamma pattern distribution from a trained model.

## Data exploration

- `il_compare_records()` scores one explicit record pair against a spec without fitting a full model, and `il_string_similarity()` computes 5 string similarity metrics for a single pair.
- `il_comparator_score()` computes batch string similarity across a DataFrame with SQL-side scoring on DuckDB.
- `il_comparator_threshold_chart()` visualizes match rates at multiple similarity thresholds.
- `il_phonetic_chart()` produces a Soundex agreement heatmap.
- `il_tf_chart()` visualizes model-specific term frequency distributions with labeled most/least common values.
- `il_register_tf()` registers pre-computed term frequency tables in the database and returns the updated model.

## Visualization

- `autoplot()` methods for `il_model`, `il_compared`, `il_training_history`, `il_accuracy`, `il_roc`, `il_precision_recall`, `il_unlinkables`, `il_completeness`, `il_count_pairs`, `il_profile`, `il_string_similarity`, `il_comparator_score`, and `il_comparison_vectors`.
- All chart types are composable with standard ggplot2 layers.

## Datasets

- `fake_1000`: 1,000 records (250 entities) for deduplication.
- `fake_1000_labels`: 3,176 pairwise labels for evaluation.
- `fake_20`: minimal 20-record example.
- `febrl4a` / `febrl4b`: 5,000-record cross-table linkage benchmark from FEBRL.

## SQL backends and persistence

- All computation runs inside a DBI-compatible database: DuckDB (recommended) or SQLite.
- Database-backed workflows support zero-copy registration from `dbplyr::tbl_lazy` references and existing table names, in addition to in-memory data frames.
- `il_save()` and `il_load()` support both RDS files and Splink settings JSON.
- `il_attach()` reattaches a saved model to different data or connections.
- `il_cleanup()` removes temporary tables owned by a single model, making it safe for shared DBI connections with multiple live models.
- `il_cleanup_all()` removes all package-owned temporary tables from a connection for exploratory sessions and failed runs.

## Performance

- Gamma computation is pushed into DuckDB using native C++ string similarity functions.
- SQLite is retained as a fallback with R-side gamma computation via `stringdist`.
- DuckDB uses SQL-native connected components, with an igraph fallback for SQLite.
- Term-frequency, lazy prediction, and scratch tables use generated model-scoped names to avoid collisions on shared connections.
- `profile_sql = TRUE` on `il_estimate_u()`, `il_estimate_prior()`, and `predict()` records lightweight SQL timing metadata for performance investigation.
- End-to-end benchmarks against an R-side SQLite baseline: 1,000 records in 1.4 s (2.1× faster), 5,000 records in 19.5 s (1.6×), 10,000 records in 61.4 s (2.6×). Speedup grows with dataset size.
