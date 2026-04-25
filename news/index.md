# Changelog

## irelink 0.0.0.9000

Initial development release, translating Python’s
[splink](https://github.com/moj-analytical-services/splink)
probabilistic record linkage engine into idiomatic R.

### Core pipeline

- [`il_spec()`](http://christophertkenny.com/irelink/reference/il_spec.md),
  [`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md),
  and
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
  define the linkage model declaratively: which fields to compare, how
  to compare them, and which blocking rules to apply.
- [`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
  binds a spec to data and a DBI connection.
- [`predict()`](https://rdrr.io/r/stats/predict.html) scores all
  candidate pairs above a match-probability threshold (or match-weight
  threshold via `threshold_match_weight`).
- [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
  resolves scored pairs into entity clusters via connected components
  (using igraph) or single-best-link (with `source_dataset` for
  cross-source filtering).

### Comparison library

- String similarity:
  [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md),
  [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md),
  [`cl_damerau_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_damerau_levenshtein.md),
  [`cl_jaro()`](http://christophertkenny.com/irelink/reference/cl_jaro.md),
  [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md),
  [`cl_jaccard()`](http://christophertkenny.com/irelink/reference/cl_jaccard.md),
  [`cl_cosine()`](http://christophertkenny.com/irelink/reference/cl_cosine.md).
- Numeric and distance:
  [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md),
  [`cl_pct_diff()`](http://christophertkenny.com/irelink/reference/cl_pct_diff.md),
  [`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md).
- Temporal:
  [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
  for date proximity with
  [`days()`](http://christophertkenny.com/irelink/reference/days.md),
  [`months()`](http://christophertkenny.com/irelink/reference/months.md),
  [`years()`](http://christophertkenny.com/irelink/reference/years.md)
  helpers;
  [`cl_time_diff()`](http://christophertkenny.com/irelink/reference/cl_time_diff.md)
  for sub-day precision with
  [`seconds()`](http://christophertkenny.com/irelink/reference/seconds.md),
  [`minutes()`](http://christophertkenny.com/irelink/reference/minutes.md),
  [`hours()`](http://christophertkenny.com/irelink/reference/hours.md)
  helpers.
- Collections:
  [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md),
  [`cl_array_subset()`](http://christophertkenny.com/irelink/reference/cl_array_subset.md),
  [`cl_array_min_distance()`](http://christophertkenny.com/irelink/reference/cl_array_min_distance.md).
- Domain-specific:
  [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md),
  [`cl_first_last_name()`](http://christophertkenny.com/irelink/reference/cl_first_last_name.md)
  /
  [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md)
  (both accept a companion column for the surname and handle first/last
  swap detection),
  [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md),
  [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md),
  `cl_domain()`,
  [`cl_zip_code()`](http://christophertkenny.com/irelink/reference/cl_zip_code.md)
  (exact, 5-digit ZIP+4, and 3-digit Sectional Center Facility prefix
  levels),
  [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md).
- Composition:
  [`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md),
  [`cl_and()`](http://christophertkenny.com/irelink/reference/cl_and.md),
  [`cl_or()`](http://christophertkenny.com/irelink/reference/cl_or.md),
  [`cl_not()`](http://christophertkenny.com/irelink/reference/cl_not.md),
  [`cl_null()`](http://christophertkenny.com/irelink/reference/cl_null.md),
  [`cl_else()`](http://christophertkenny.com/irelink/reference/cl_else.md),
  [`cl_literal()`](http://christophertkenny.com/irelink/reference/cl_literal.md),
  [`cl_custom()`](http://christophertkenny.com/irelink/reference/cl_custom.md),
  [`cl_columns_reversed()`](http://christophertkenny.com/irelink/reference/cl_columns_reversed.md).
- All applicable comparators accept `term_frequency = TRUE` for
  Fellegi-Sunter term-frequency adjustments.

### Column transforms

- [`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md)
  composes multiple R functions into a chainable transform with SQL-side
  nesting (e.g. `TRIM(LOWER(col))`).
- Column transform factories for SQL-side column expressions:
  [`il_substr()`](http://christophertkenny.com/irelink/reference/il_substr.md),
  [`il_regex_extract()`](http://christophertkenny.com/irelink/reference/il_regex_extract.md),
  [`il_nullif()`](http://christophertkenny.com/irelink/reference/il_nullif.md),
  [`il_cast_to_string()`](http://christophertkenny.com/irelink/reference/il_cast_to_string.md),
  [`il_try_parse_date()`](http://christophertkenny.com/irelink/reference/il_try_parse_date.md),
  [`il_array_element()`](http://christophertkenny.com/irelink/reference/il_array_element.md).
- Built-in transforms auto-translated to SQL: `tolower`, `toupper`,
  `trimws`.
- Phonetic transforms:
  [`il_soundex()`](http://christophertkenny.com/irelink/reference/phonetic.md),
  [`il_metaphone()`](http://christophertkenny.com/irelink/reference/phonetic.md),
  [`il_dmetaphone()`](http://christophertkenny.com/irelink/reference/phonetic.md)
  (usable as R functions and SQL macros).

### Blocking

- [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
  and
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md)
  for equality-based and custom SQL blocking rules.
- `.explode` parameter for array-valued blocking columns (generates
  `UNNEST` subqueries for DuckDB/PostgreSQL).
- [`il_suggest_blocking()`](http://christophertkenny.com/irelink/reference/il_suggest_blocking.md)
  ranks candidate blocking rules by pair-reduction, coverage, and
  balanced score.
- [`il_find_blocking_below()`](http://christophertkenny.com/irelink/reference/il_find_blocking_below.md)
  finds blocking rule combinations below a pair count ceiling.
- [`block_from_labels()`](http://christophertkenny.com/irelink/reference/block_from_labels.md)
  measures per-column recall from labelled pairs.

### Training

- [`il_estimate_u()`](http://christophertkenny.com/irelink/reference/il_estimate_u.md)
  estimates non-match probabilities by sampling random pairs.
- [`il_estimate_em()`](http://christophertkenny.com/irelink/reference/il_estimate_em.md)
  runs the Fellegi-Sunter EM algorithm with configurable
  `max_iterations`, `convergence`, `fix_u`, `fix_m`, `fix_prior`,
  `derive_prior`, and `estimate_without_tf` parameters.
- [`il_estimate_prior()`](http://christophertkenny.com/irelink/reference/il_estimate_prior.md)
  sets the prior match probability.
- [`il_estimate_m_from_labels()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_labels.md)
  and
  [`il_estimate_m_from_column()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_column.md)
  initialise parameters from ground-truth labels.

### Prediction

- [`predict()`](https://rdrr.io/r/stats/predict.html) supports both
  `threshold` (match probability) and `threshold_match_weight` (log₂
  Bayes factor) filtering.
- `include_fields = TRUE` joins all source columns into the scored
  output.
- `collect = FALSE` returns an `il_compared_lazy` object backed by an
  in-database table.
- [`il_score_missing_edges()`](http://christophertkenny.com/irelink/reference/il_score_missing_edges.md)
  enumerates and scores unscored within-cluster pairs.
- [`il_deterministic_link()`](http://christophertkenny.com/irelink/reference/il_deterministic_link.md)
  performs exact-match linking without training.
- [`il_find_matches()`](http://christophertkenny.com/irelink/reference/il_find_matches.md)
  scores a set of probe records against existing data.

### Diagnostics and evaluation

- [`il_parameters()`](http://christophertkenny.com/irelink/reference/il_parameters.md)
  and
  [`il_weights()`](http://christophertkenny.com/irelink/reference/il_weights.md)
  expose the learned m/u parameters.
- [`il_waterfall()`](http://christophertkenny.com/irelink/reference/il_waterfall.md)
  decomposes a pair’s match weight into per-comparison contributions.
- [`il_training_history()`](http://christophertkenny.com/irelink/reference/il_training_history.md)
  tracks parameter convergence across EM iterations.
- [`il_completeness()`](http://christophertkenny.com/irelink/reference/il_completeness.md)
  and
  [`il_profile()`](http://christophertkenny.com/irelink/reference/il_profile.md)
  summarise data quality;
  [`il_profile()`](http://christophertkenny.com/irelink/reference/il_profile.md)
  accepts raw SQL expressions as column definitions (e.g.,
  `"city || left(first_name, 1)"`).
- [`il_unlinkables()`](http://christophertkenny.com/irelink/reference/il_unlinkables.md)
  identifies records that cannot be linked under any blocking rule.
- [`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md),
  [`il_precision_recall()`](http://christophertkenny.com/irelink/reference/il_precision_recall.md),
  and
  [`il_roc()`](http://christophertkenny.com/irelink/reference/il_roc.md)
  evaluate performance against labelled data.
- [`il_errors()`](http://christophertkenny.com/irelink/reference/il_errors.md)
  surfaces false positives and false negatives.
- [`il_graph_metrics()`](http://christophertkenny.com/irelink/reference/il_graph_metrics.md)
  computes node degree, node centrality, cluster density, cluster
  centralisation, and bridge detection.
- [`il_comparison_vectors()`](http://christophertkenny.com/irelink/reference/il_comparison_vectors.md)
  returns the gamma pattern distribution from a trained model.

### Data exploration

- [`il_string_similarity()`](http://christophertkenny.com/irelink/reference/il_string_similarity.md)
  computes 5 string similarity metrics for a single pair.
- [`il_comparator_score()`](http://christophertkenny.com/irelink/reference/il_comparator_score.md)
  computes batch string similarity across a DataFrame with SQL-side
  scoring on DuckDB/PostgreSQL.
- [`il_comparator_threshold_chart()`](http://christophertkenny.com/irelink/reference/il_comparator_threshold_chart.md)
  visualises match rates at multiple similarity thresholds.
- [`il_phonetic_chart()`](http://christophertkenny.com/irelink/reference/il_phonetic_chart.md)
  produces a Soundex agreement heatmap.
- [`il_tf_chart()`](http://christophertkenny.com/irelink/reference/il_tf_chart.md)
  visualises term frequency distributions with labelled most/least
  common values.
- [`il_register_tf()`](http://christophertkenny.com/irelink/reference/il_register_tf.md)
  registers pre-computed term frequency tables in the database.

### Visualisation

- [`autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
  methods for `il_model`, `il_compared`, `il_training_history`,
  `il_accuracy`, `il_roc`, `il_precision_recall`, `il_unlinkables`,
  `il_completeness`, `il_count_pairs`, `il_profile`,
  `il_string_similarity`, `il_comparator_score`, and
  `il_comparison_vectors`.
- All chart types are composable with standard ggplot2 layers.

### Datasets

- `fake_1000`: 1,000 records (250 entities) for deduplication.
- `fake_1000_labels`: 3,176 pairwise labels for evaluation.
- `fake_20`: minimal 20-record example.
- `febrl4a` / `febrl4b`: 5,000-record cross-table linkage benchmark from
  FEBRL.

### SQL backends and persistence

- All computation runs inside a DBI-compatible database: DuckDB
  (recommended), SQLite, or PostgreSQL.
- [`il_save()`](http://christophertkenny.com/irelink/reference/il_save.md)
  and
  [`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md)
  support both RDS files and Splink settings JSON.
- [`il_attach()`](http://christophertkenny.com/irelink/reference/il_attach.md)
  reattaches a saved model to different data or connections.
- [`il_cleanup()`](http://christophertkenny.com/irelink/reference/il_cleanup.md)
  removes temporary tables from the database.

### Performance

- Gamma computation is pushed into DuckDB using native C++ string
  similarity functions.
- SQLite is retained as a fallback with R-side gamma computation via
  `stringdist`.
- SQL-native connected components for DuckDB/PostgreSQL; igraph fallback
  for SQLite.
- End-to-end benchmarks against an R-side SQLite baseline: 1,000 records
  in 1.4 s (2.1× faster), 5,000 records in 19.5 s (1.6×), 10,000 records
  in 61.4 s (2.6×). Speedup grows with dataset size.
