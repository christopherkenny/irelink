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
  candidate pairs above a match-probability threshold.
- [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
  resolves scored pairs into entity clusters via connected components
  (using igraph) or single-best-link.

### Comparison library

- [`cl_first_last_name()`](http://christophertkenny.com/irelink/reference/cl_first_last_name.md)
  is an American-English alias for
  [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md).
  Both accept a companion column argument (`last_name` / `surname`) and
  a `term_frequency` flag.
- [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md)
  accepts a `surname` argument (default `'surname'`) so the companion
  column name can be specified explicitly. This also fixes a bug where
  the swap-detection SQL referenced unresolved `{col_forename}` and
  `{col_surname}` variables at runtime.
- [`cl_zip_code()`](http://christophertkenny.com/irelink/reference/cl_zip_code.md)
  is a domain comparison for US ZIP codes with levels for exact match,
  5-digit prefix (ZIP+4 normalization), and 3-digit Sectional Center
  Facility prefix.
- [`cl_damerau_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_damerau_levenshtein.md),
  [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md),
  [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md),
  [`cl_jaro()`](http://christophertkenny.com/irelink/reference/cl_jaro.md),
  [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md),
  [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md),
  [`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md),
  [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md),
  and
  [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md)
  accept `term_frequency = TRUE` to apply Fellegi-Sunter term-frequency
  adjustments at the highest comparison level, giving rare values higher
  match weights than common ones.
- [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md)
  for exact matches.
- [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md)
  and
  [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md)
  for fuzzy strings.
- [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
  for temporal proximity.
- [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md)
  for numerical distance.
- [`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md)
  for geographic coordinates.
- [`cl_cosine()`](http://christophertkenny.com/irelink/reference/cl_cosine.md),
  [`cl_jaccard()`](http://christophertkenny.com/irelink/reference/cl_jaccard.md),
  and
  [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md)
  for set-valued fields.
- `cl_domain()` for email domains;
  [`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md)
  for categorical variables.
- [`cl_custom()`](http://christophertkenny.com/irelink/reference/cl_custom.md)
  for arbitrary SQL expressions.

### Training

- [`il_estimate_u()`](http://christophertkenny.com/irelink/reference/il_estimate_u.md)
  estimates non-match probabilities by sampling random pairs across all
  blocking rules.
- [`il_estimate_em()`](http://christophertkenny.com/irelink/reference/il_estimate_em.md)
  runs the Fellegi-Sunter EM algorithm to learn match probabilities
  without labelled data. Multiple passes with different blocking rules
  iteratively refine the parameters.
- [`il_estimate_prior()`](http://christophertkenny.com/irelink/reference/il_estimate_prior.md)
  sets the prior match probability.
- [`il_estimate_m_from_labels()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_labels.md)
  and
  [`il_estimate_m_from_column()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_column.md)
  initialise parameters from ground-truth labels when available.

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
  summarise data quality.
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
  summarises cluster-level statistics.
- [`autoplot()`](https://ggplot2.tidyverse.org/reference/autoplot.html)
  methods produce ggplot2 charts from model inspection outputs.

### Data exploration

- [`il_profile()`](http://christophertkenny.com/irelink/reference/il_profile.md)
  accepts raw SQL expressions as character strings in addition to bare
  column names (e.g.,
  `il_profile(df, "city || left(first_name, 1)", con = con)`). The
  expression is passed directly to the database `GROUP BY`, matching the
  behaviour of splink’s `column_expressions` argument.

### Prediction

- [`predict()`](https://rdrr.io/r/stats/predict.html) supports
  `include_fields = TRUE` when `collect = FALSE`. The original field
  values are joined into the in-database scored-pairs table before
  `__il_predicted` is created, so field columns are available without a
  separate R-side join.

### SQL backends and persistence

- All computation runs inside a DBI-compatible database: DuckDB
  (recommended), SQLite, or PostgreSQL.
- [`il_deterministic_link()`](http://christophertkenny.com/irelink/reference/il_deterministic_link.md)
  performs exact-match linking without training.
- [`il_save()`](http://christophertkenny.com/irelink/reference/il_save.md)
  and
  [`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md)
  use R’s native RDS format instead of JSON. RDS handles nested R
  objects (comparison levels, transforms, tibble params) without any
  lossy type coercion, removing the reconstruction code that was
  required for JSON round-trips.
- [`il_cleanup()`](http://christophertkenny.com/irelink/reference/il_cleanup.md)
  removes temporary tables from the database.

### Performance

- Gamma (comparison level) computation is pushed into DuckDB using its
  native C++ string similarity functions, so only compact IDs and
  integer gamma columns cross the R-SQL boundary.
- SQLite is retained as a fallback with R-side gamma computation via
  `stringdist`.
- End-to-end benchmarks against the original SQLite baseline: 1,000
  records in 1.4 s (2.1× faster), 5,000 records in 19.5 s (1.6×), 10,000
  records in 61.4 s (2.6×). Speedup grows with dataset size.
