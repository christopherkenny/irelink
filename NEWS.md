# irelink 0.0.0.9000

Initial development release, translating Python's [splink](https://github.com/moj-analytical-services/splink) probabilistic record linkage engine into idiomatic R.

## Core pipeline

- `il_spec()`, `il_compare()`, and `il_block_on()` define the linkage model declaratively: which fields to compare, how to compare them, and which blocking rules to apply.
- `il_model()` binds a spec to data and a DBI connection.
- `predict()` scores all candidate pairs above a match-probability threshold (or match-weight threshold via `threshold_match_weight`).
- `il_cluster()` resolves scored pairs into entity clusters via connected components (using igraph) or single-best-link (with `source_dataset` for cross-source filtering).

## Comparison library

- String similarity: `cl_exact()`, `cl_levenshtein()`, `cl_damerau_levenshtein()`, `cl_jaro()`, `cl_jaro_winkler()`, `cl_jaccard()`, `cl_cosine()`.
- Numeric and distance: `cl_numeric_diff()`, `cl_pct_diff()`, `cl_distance_km()`.
- Temporal: `cl_date_diff()` for date proximity with `days()`, `months()`, `years()` helpers; `cl_time_diff()` for sub-day precision with `seconds()`, `minutes()`, `hours()` helpers.
- Collections: `cl_array_intersect()`, `cl_array_subset()`, `cl_array_min_distance()`.
- Domain-specific: `cl_name()`, `cl_first_last_name()` / `cl_forename_surname()` (both accept a companion column for the surname and handle first/last swap detection), `cl_dob()`, `cl_email()`, `cl_domain()`, `cl_zip_code()` (exact, 5-digit ZIP+4, and 3-digit Sectional Center Facility prefix levels), `cl_postcode()`.
- Composition: `cl_levels()`, `cl_and()`, `cl_or()`, `cl_not()`, `cl_null()`, `cl_else()`, `cl_literal()`, `cl_custom()`, `cl_columns_reversed()`.
- All applicable comparators accept `term_frequency = TRUE` for Fellegi-Sunter term-frequency adjustments.

## Column transforms

- `il_transform()` composes multiple R functions into a chainable transform with SQL-side nesting (e.g. `TRIM(LOWER(col))`).
- Column transform factories for SQL-side column expressions: `il_substr()`, `il_regex_extract()`, `il_nullif()`, `il_cast_to_string()`, `il_try_parse_date()`, `il_array_element()`.
- Built-in transforms auto-translated to SQL: `tolower`, `toupper`, `trimws`.
- Phonetic transforms: `il_soundex()`, `il_metaphone()`, `il_dmetaphone()` (usable as R functions and SQL macros).

## Blocking

- `il_block_on()` and `block_on()` for equality-based and custom SQL blocking rules.
- `.explode` parameter for array-valued blocking columns (generates `UNNEST` subqueries for DuckDB/PostgreSQL).
- `il_suggest_blocking()` ranks candidate blocking rules by pair-reduction, coverage, and balanced score.
- `il_find_blocking_below()` finds blocking rule combinations below a pair count ceiling.
- `block_from_labels()` measures per-column recall from labelled pairs.

## Training

- `il_estimate_u()` estimates non-match probabilities by sampling random pairs.
- `il_estimate_em()` runs the Fellegi-Sunter EM algorithm with configurable `max_iterations`, `convergence`, `fix_u`, `fix_m`, `fix_prior`, `derive_prior`, and `estimate_without_tf` parameters.
- `il_estimate_prior()` sets the prior match probability.
- `il_estimate_m_from_labels()` and `il_estimate_m_from_column()` initialise parameters from ground-truth labels.

## Prediction

- `predict()` supports both `threshold` (match probability) and `threshold_match_weight` (log₂ Bayes factor) filtering.
- `include_fields = TRUE` joins all source columns into the scored output.
- `collect = FALSE` returns an `il_compared_lazy` object backed by an in-database table.
- `il_score_missing_edges()` enumerates and scores unscored within-cluster pairs.
- `il_deterministic_link()` performs exact-match linking without training.
- `il_find_matches()` scores a set of probe records against existing data.

## Diagnostics and evaluation

- `il_parameters()` and `il_weights()` expose the learned m/u parameters.
- `il_waterfall()` decomposes a pair's match weight into per-comparison contributions.
- `il_training_history()` tracks parameter convergence across EM iterations.
- `il_completeness()` and `il_profile()` summarise data quality; `il_profile()` accepts raw SQL expressions as column definitions (e.g., `"city || left(first_name, 1)"`).
- `il_unlinkables()` identifies records that cannot be linked under any blocking rule.
- `il_accuracy()`, `il_precision_recall()`, and `il_roc()` evaluate performance against labelled data.
- `il_errors()` surfaces false positives and false negatives.
- `il_graph_metrics()` computes node degree, node centrality, cluster density, cluster centralisation, and bridge detection.
- `il_comparison_vectors()` returns the gamma pattern distribution from a trained model.

## Data exploration

- `il_string_similarity()` computes 5 string similarity metrics for a single pair.
- `il_comparator_score()` computes batch string similarity across a DataFrame with SQL-side scoring on DuckDB/PostgreSQL.
- `il_comparator_threshold_chart()` visualises match rates at multiple similarity thresholds.
- `il_phonetic_chart()` produces a Soundex agreement heatmap.
- `il_tf_chart()` visualises term frequency distributions with labelled most/least common values.
- `il_register_tf()` registers pre-computed term frequency tables in the database.

## Visualisation

- `autoplot()` methods for `il_model`, `il_compared`, `il_training_history`, `il_accuracy`, `il_roc`, `il_precision_recall`, `il_unlinkables`, `il_completeness`, `il_count_pairs`, `il_profile`, `il_string_similarity`, `il_comparator_score`, and `il_comparison_vectors`.
- All chart types are composable with standard ggplot2 layers.

## Datasets

- `fake_1000`: 1,000 records (250 entities) for deduplication.
- `fake_1000_labels`: 3,176 pairwise labels for evaluation.
- `fake_20`: minimal 20-record example.
- `febrl4a` / `febrl4b`: 5,000-record cross-table linkage benchmark from FEBRL.

## SQL backends and persistence

- All computation runs inside a DBI-compatible database: DuckDB (recommended), SQLite, or PostgreSQL.
- `il_save()` and `il_load()` use R's native RDS format, which handles nested R objects (comparison levels, transforms, tibble params) without lossy type coercion.
- `il_attach()` reattaches a saved model to different data or connections.
- `il_cleanup()` removes temporary tables from the database.

## Performance

- Gamma computation is pushed into DuckDB using native C++ string similarity functions.
- SQLite is retained as a fallback with R-side gamma computation via `stringdist`.
- SQL-native connected components for DuckDB/PostgreSQL; igraph fallback for SQLite.
- End-to-end benchmarks against an R-side SQLite baseline: 1,000 records in 1.4 s (2.1× faster), 5,000 records in 19.5 s (1.6×), 10,000 records in 61.4 s (2.6×). Speedup grows with dataset size.
