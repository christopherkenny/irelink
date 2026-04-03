# irelink 0.0.0.9000

Initial development release, translating Python's [splink](https://github.com/moj-analytical-services/splink) probabilistic record linkage engine into idiomatic R.

## Core pipeline

- `il_spec()`, `il_compare()`, and `il_block_on()` define the linkage model declaratively: which fields to compare, how to compare them, and which blocking rules to apply.
- `il_model()` binds a spec to data and a DBI connection.
- `predict()` scores all candidate pairs above a match-probability threshold.
- `il_cluster()` resolves scored pairs into entity clusters via connected components (using igraph) or single-best-link.

## Comparison library

- `cl_first_last_name()` is a new American-English alias for `cl_forename_surname()`. Both accept a companion column argument (`last_name` / `surname`) and a `term_frequency` flag.
- `cl_forename_surname()` now accepts a `surname` argument (default `'surname'`) so the companion column name can be specified explicitly. This also fixes a bug where the swap-detection SQL referenced unresolved `{col_forename}` and `{col_surname}` variables at runtime.
- `cl_zip_code()` is a new domain comparison for US ZIP codes with levels for exact match, 5-digit prefix (ZIP+4 normalization), and 3-digit Sectional Center Facility prefix.
- `cl_damerau_levenshtein()`, `cl_dob()`, `cl_email()`, `cl_jaro()`, `cl_jaro_winkler()`, `cl_levenshtein()`, `cl_levels()`, `cl_name()`, and `cl_postcode()` now accept `term_frequency = TRUE` to apply Fellegi-Sunter term-frequency adjustments at the highest comparison level, giving rare values higher match weights than common ones.
- `cl_exact()` for exact matches.
- `cl_jaro_winkler()` and `cl_levenshtein()` for fuzzy strings.
- `cl_date_diff()` for temporal proximity.
- `cl_numeric_diff()` for numerical distance.
- `cl_distance_km()` for geographic coordinates.
- `cl_cosine()`, `cl_jaccard()`, and `cl_array_intersect()` for set-valued fields.
- `cl_domain()` for email domains; `cl_levels()` for categorical variables.
- `cl_custom()` for arbitrary SQL expressions.

## Training

- `il_estimate_u()` estimates non-match probabilities by sampling random pairs across all blocking rules.
- `il_estimate_em()` runs the Fellegi-Sunter EM algorithm to learn match probabilities without labelled data. Multiple passes with different blocking rules iteratively refine the parameters.
- `il_estimate_prior()` sets the prior match probability.
- `il_estimate_m_from_labels()` and `il_estimate_m_from_column()` initialise parameters from ground-truth labels when available.

## Diagnostics and evaluation

- `il_parameters()` and `il_weights()` expose the learned m/u parameters.
- `il_waterfall()` decomposes a pair's match weight into per-comparison contributions.
- `il_training_history()` tracks parameter convergence across EM iterations.
- `il_completeness()` and `il_profile()` summarise data quality.
- `il_unlinkables()` identifies records that cannot be linked under any blocking rule.
- `il_accuracy()`, `il_precision_recall()`, and `il_roc()` evaluate performance against labelled data.
- `il_errors()` surfaces false positives and false negatives.
- `il_graph_metrics()` summarises cluster-level statistics.
- `autoplot()` methods produce ggplot2 charts from model inspection outputs.

## Data exploration

- `il_profile()` now accepts raw SQL expressions as character strings in addition to bare column names (e.g., `il_profile(df, "city || left(first_name, 1)", con = con)`). The expression is passed directly to the database `GROUP BY`, matching the behaviour of splink's `column_expressions` argument.

## Prediction

- `predict()` now supports `include_fields = TRUE` when `collect = FALSE`. The original field values are joined into the in-database scored-pairs table before `__il_predicted` is created, so field columns are available without a separate R-side join. Previously `include_fields` was silently ignored on the lazy path.

## SQL backends and persistence

- All computation runs inside a DBI-compatible database: DuckDB (recommended), SQLite, or PostgreSQL.
- `il_deterministic_link()` performs exact-match linking without training.
- `il_save()` serialises a trained model to JSON for later reuse.
- `il_cleanup()` removes temporary tables from the database.

## Performance

- Gamma (comparison level) computation is pushed into DuckDB using its native C++ string similarity functions, so only compact IDs and integer gamma columns cross the R-SQL boundary.
- SQLite is retained as a fallback with R-side gamma computation via `stringdist`.
- End-to-end benchmarks against the original SQLite baseline: 1,000 records in 1.4 s (2.1× faster), 5,000 records in 19.5 s (1.6×), 10,000 records in 61.4 s (2.6×). Speedup grows with dataset size.
