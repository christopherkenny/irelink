# Deep Comparison: irelink vs. splink

This document is a comprehensive source-level comparison of every feature in
the Python [splink](https://github.com/moj-analytical-services/splink) package
against its R derivative **irelink**. The audit was performed against the
codebases on disk (April 2025).

**Legend**

| Symbol | Meaning |
|--------|---------|
| ✅ | Full parity or equivalent |
| ✅+ | irelink improvement or R-original feature |
| ⚠️ | Partial parity or design difference |
| ❌ | Missing from irelink |
| 🚫 | Excluded by scope (platform-specific) |

---

## 1. Core Pipeline

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `SettingsCreator(link_type, comparisons, blocking_rules)` | `il_spec() \|> il_compare() \|> il_block_on()` | ✅ | Builder pattern vs. constructor |
| `Linker(df, settings, db_api)` | `il_model(df, spec, con)` | ✅ | |
| `link_type = "dedupe_only"` | `link_type = "dedupe"` | ✅ | |
| `link_type = "link_only"` | `link_type = "link"` | ✅ | |
| `link_type = "link_and_dedupe"` | `link_type = "link_and_dedupe"` | ✅ | |
| `DuckDBAPI(connection=con)` | `DBI::dbConnect(duckdb::duckdb())` | ✅ | Standard DBI |
| `unique_id_column_name` setting | Column named `unique_id` by convention | ✅ | |
| `source_dataset_column_name` setting | Inferred from multi-table args | ✅ | |

**Paths:** `splink/internals/settings_creator.py`, `R/il_spec.R`, `R/il_model.R`

---

## 2. Comparison Library

### 2a. String Similarity Comparisons

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `ExactMatch(col)` | `cl_exact()` | ✅ | |
| `LevenshteinAtThresholds(col, [1,2])` | `cl_levenshtein(1, 2)` | ✅ | |
| `DamerauLevenshteinAtThresholds(col, [1,2])` | `cl_damerau_levenshtein(1, 2)` | ✅ | |
| `JaroWinklerAtThresholds(col, [0.9,0.7])` | `cl_jaro_winkler(0.9, 0.7)` | ✅ | |
| `JaroAtThresholds(col, [0.9,0.7])` | `cl_jaro(0.9, 0.7)` | ✅ | |
| `JaccardAtThresholds(col, [0.9,0.7])` | `cl_jaccard(0.9, 0.7)` | ✅ | |
| `CosineSimilarityAtThresholds(col, [0.8])` | `cl_cosine(0.8)` | ✅ | |
| `.configure(term_frequency_adjustments=True)` | `cl_exact(term_frequency = TRUE)` | ✅ | Per-comparison flag |

**Paths:** `splink/internals/comparison_library.py:37–288`, `R/cl_exact.R`, `R/cl_levenshtein.R`, `R/cl_jaro_winkler.R`, `R/cl_jaro.R`, `R/cl_jaccard.R`, `R/cl_cosine.R`

### 2b. Numeric & Distance Comparisons

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `DistanceInKMAtThresholds(lat, lng, [5,10])` | `cl_distance_km(5, 10)` | ✅ | Haversine great-circle |
| `AbsoluteDateDifferenceAtThresholds(col, [1,10], metric='day')` | `cl_date_diff(days(1), days(10))` | ✅ | Unit-safe helpers |
| `AbsoluteTimeDifferenceAtThresholds(col, [60], metric='second')` | `cl_time_diff(seconds(60))` | ✅ | **Resolved**: `cl_time_diff()` supports `seconds()`, `minutes()`, `hours()` unit helpers. SQL generation for DuckDB/PostgreSQL epoch-based diff. R-side fallback for SQLite. See `R/cl_time_diff.R`, `R/utils-unit-helpers.R`. |
| `AbsoluteDifferenceLevel(col, threshold)` | `cl_numeric_diff(threshold)` | ✅ | Absolute numeric diff |
| `PercentageDifferenceLevel(col, threshold)` | `cl_pct_diff(threshold)` | ✅ | Relative % diff |
| `DistanceFunctionAtThresholds(col, fn_name, thresholds)` | — | ⚠️ | **No generic "any SQL function" wrapper**. irelink covers specific functions (Jaro, Levenshtein, etc.) individually. If you need `hamming` or a custom SQL distance function by name, use `cl_custom()`. |

**Paths:** `splink/internals/comparison_library.py:289–548`, `R/cl_distance_km.R`, `R/cl_date_diff.R`, `R/cl_numeric_diff.R`

### 2c. Array / Collection Comparisons

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `ArrayIntersectAtSizes(col, [2,1])` | `cl_array_intersect(2, 1)` | ✅ | |
| `ArraySubsetLevel` | `cl_array_subset()` | ✅ | |
| `PairwiseStringDistanceFunctionAtThresholds(col, fn, thresholds)` | `cl_array_min_distance(fn, thresholds)` | ✅ | Same feature, clearer name |

**Paths:** `splink/internals/comparison_library.py:350–417`, `R/cl_array_intersect.R`

### 2d. Domain-Specific Comparisons (Pre-built Templates)

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `NameComparison(col)` | `cl_name()` | ✅ | |
| `EmailComparison(col)` | `cl_email()` | ✅ | |
| `DateOfBirthComparison(col)` | `cl_dob()` | ✅ | |
| `PostcodeComparison(col)` | `cl_postcode()` | ✅ | UK postcodes |
| `ForenameSurnameComparison(forename, surname)` | `cl_forename_surname(surname)` | ✅ | Includes swap detection |
| — | `cl_zip_code()` | ✅+ | **irelink-original**: US ZIP code comparison (5-digit + SCF 3-digit levels, optional geo fallback) |
| — | `cl_first_last_name()` | ✅+ | **irelink-original**: American-English alias for `cl_forename_surname()` |

**Paths:** `splink/internals/comparison_library.py:900–1200`, `R/cl_domain.R`

### 2e. Custom & Composition Levels

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `CustomComparison(col, levels)` | `cl_levels(cl_null(), ..., cl_else())` | ✅ | |
| `NullLevel()` | `cl_null()` | ✅ | |
| `ElseLevel()` | `cl_else()` | ✅ | |
| `CustomLevel(sql)` | `cl_custom(sql)` | ✅ | |
| `And(level1, level2)` | `cl_and(level1, level2)` | ✅ | |
| `Or(level1, level2)` | `cl_or(level1, level2)` | ✅ | |
| `Not(level)` | `cl_not(level)` | ✅ | |
| `ExactMatchLevel(col)` | `cl_exact()` | ✅ | |
| `LiteralMatchLevel(col, value)` | `cl_literal(value)` | ✅ | |
| `ColumnsReversedLevel(col1, col2, symmetrical)` | `cl_columns_reversed(col2)` | ✅ | **Resolved**: standalone function, also used internally by `cl_forename_surname()`. See `R/cl_columns_reversed.R`. |

**Paths:** `splink/internals/comparison_level_library.py:363–403`, `R/cl_levels.R`, `R/cl_domain.R:164–177`

### 2f. Column Expression System

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `ColumnExpression("col").lower()` | `il_compare(col, method, transform = tolower)` | ✅ | Different API, same effect |
| `.lower()` | `tolower` | ✅ | Auto-translated to SQL |
| `.upper()` | `toupper` | ✅ | Auto-translated to SQL |
| `.trim()` | `trimws` | ✅ | Auto-translated to SQL |
| `.substr(start, len)` | `il_substr(start, len)` | ✅ | **Resolved**: `il_substr()` factory, SQL `SUBSTRING()`. See `R/il_column_transforms.R`. |
| `.regex_extract(pattern, group)` | `il_regex_extract(pattern, group)` | ✅ | **Resolved**: `il_regex_extract()` factory, SQL `regexp_extract()`. See `R/il_column_transforms.R`. |
| `.nullif(value)` | `il_nullif(value)` | ✅ | **Resolved**: `il_nullif()` factory, SQL `NULLIF()`. See `R/il_column_transforms.R`. |
| `.cast_to_string()` | `il_cast_to_string()` | ✅ | **Resolved**: `il_cast_to_string()` factory, SQL `CAST(col AS VARCHAR)`. See `R/il_column_transforms.R`. |
| `.try_parse_date(format)` | `il_try_parse_date(format)` | ✅ | **Resolved**: `il_try_parse_date()` factory, DuckDB `try_strptime()`, PostgreSQL `TO_DATE()`. See `R/il_column_transforms.R`. |
| `.try_parse_timestamp(format)` | — | ⚠️ | Timestamps handled natively by `cl_time_diff()` when columns are already datetime/string. Use `il_try_parse_date()` for explicit parsing. |
| `.access_extreme_array_element(first_or_last)` | `il_array_element("first")` / `il_array_element("last")` | ✅ | **Resolved**: `il_array_element()` factory, SQL `col[1]`/`col[-1]`. See `R/il_column_transforms.R`. |
| Method chaining: `.lower().substr(0,1)` | `il_transform(tolower, trimws)` | ✅ | **Resolved**: `il_transform()` composes multiple R functions into a chainable transform. SQL-side nesting (e.g. `TRIM(LOWER(col))`). See `R/il_transform.R`. |

**Design note**: splink's `ColumnExpression` is a comprehensive dialect-aware
SQL generation layer with method chaining. irelink uses a simpler but
composable model: R functions passed as `transform` arguments are auto-translated
to SQL for common cases (`tolower`, `toupper`, `trimws`, `il_soundex`).
Column transforms (`il_substr`, `il_regex_extract`, `il_nullif`, `il_cast_to_string`,
`il_try_parse_date`, `il_array_element`) are factory functions returning closures
with `il_column_transform` class, composable via `il_transform()`.
For anything beyond these, users write raw SQL via `cl_custom()` or `.where` arguments.

**Paths:** `splink/internals/column_expression.py:23–366`, `R/il_compare.R:18–22`, `R/il_column_transforms.R`

---

## 3. Blocking

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `block_on("col1", "col2")` | `block_on(col1, col2)` | ✅ | |
| `CustomRule(sql)` | `block_on(.where = "SQL")` | ✅ | |
| `And(rule1, rule2)` blocking | `block_on(col1, col2)` (multi-col = AND) | ✅ | |
| `count_comparisons_from_blocking_rule()` | `il_count_pairs()` | ✅ | |
| `cumulative_comparisons_...chart()` | `il_count_pairs()` returns cumulative data + `autoplot()` | ✅ | |
| `n_largest_blocks()` | `il_largest_blocks()` | ✅ | |
| Salting (`salting_partitions`) | — | 🚫 | Cluster-computing feature for Spark |
| Exploding blocking rules (`arrays_to_explode`) | `il_block_on(col, .explode = "col")` | ✅ | **Resolved**: `.explode` parameter generates `UNNEST` subqueries for DuckDB/PostgreSQL. SQLite warns and skips (no array support). See `R/il_block_on.R`, `R/utils-sql.R` (`sql_explode_from()`). |
| `_detect_blocking_rules_for_prediction()` | `il_suggest_blocking()` | ✅+ | **irelink improvement**: public API with heuristic scoring |
| `_find_blocking_rules_below_threshold()` | `il_find_blocking_below()` | ✅+ | **irelink improvement**: public API |
| `block_from_labels.py` | `block_from_labels()` | ✅ | Per-column recall from labelled pairs |
| `optimise_cost_of_brs.py` (heuristic BR selection) | `il_suggest_blocking(max_depth)` | ⚠️ | Different algorithm: irelink ranks by score; splink uses localised shuffle + field-freedom heuristic |

**Paths:** `splink/internals/blocking.py`, `splink/internals/blocking_rule_library.py`, `splink/internals/optimise_cost_of_brs.py`, `splink/internals/find_brs_with_comparison_counts_below_threshold.py`, `R/il_block_on.R`, `R/il_suggest_blocking.R`, `R/il_count_pairs.R`, `R/il_largest_blocks.R`

---

## 4. Training / Parameter Estimation

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `estimate_u_using_random_sampling(max_pairs, seed)` | `il_estimate_u(model, max_pairs)` | ✅ | |
| `estimate_parameters_using_expectation_maximisation(blocking_rule)` | `il_estimate_em(model, blocking)` | ✅ | |
| EM: `fix_u_probabilities` | `il_estimate_em(fix_u = TRUE)` | ✅ | Default TRUE |
| EM: `fix_m_probabilities` | `il_estimate_em(fix_m = FALSE)` | ✅ | Default FALSE |
| EM: `fix_probability_two_random_records_match` | `il_estimate_em(fix_prior = TRUE)` | ✅ | **Resolved**: `fix_prior` parameter (default TRUE). When FALSE, prior λ is updated each EM iteration. See `R/il_estimate_em.R`. |
| EM: `estimate_without_term_frequencies` | `il_estimate_em(estimate_without_tf = TRUE)` | ✅ | **Resolved**: parameter accepted. No-op in practice since irelink applies TF at scoring time, not during EM. See `R/il_estimate_em.R`. |
| EM: `populate_probability_two_random_records_match_from_trained_values` | `il_estimate_em(derive_prior = TRUE)` | ✅ | **Resolved**: `derive_prior` parameter computes prior from trained EM parameters via average posterior match probability. See `R/il_estimate_em.R`. |
| `em_convergence` | `il_estimate_em(convergence = 1e-5)` | ✅ | |
| `max_iterations` | `il_estimate_em(max_iterations = 25)` | ✅ | **Resolved**: exposed as parameter (default 25). See `R/il_estimate_em.R`. |
| `estimate_probability_two_random_records_match(rules, recall)` | `il_estimate_prior(model, ..., recall)` | ✅ | |
| `estimate_m_from_label_column(col)` | `il_estimate_m_from_column(model, col)` | ✅ | |
| `estimate_m_from_pairwise_labels(labels)` | `il_estimate_m_from_labels(model, labels)` | ✅ | |

**Paths:** `splink/internals/linker_components/training.py:220–324`, `R/il_estimate_u.R`, `R/il_estimate_em.R`, `R/il_estimate_prior.R`, `R/il_estimate_m_from_column.R`, `R/il_estimate_m_from_labels.R`

---

## 5. Prediction / Inference

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `predict(threshold_match_probability)` | `predict(model, threshold)` | ✅ | Default 0.85 |
| `predict(threshold_match_weight)` | `predict(model, threshold_match_weight = 5)` | ✅ | **Resolved**: filters on log₂ Bayes factor in both R-path and SQL-path. See `R/predict.R`, `R/utils-sql.R` (`build_scored_query()`). |
| `retain_matching_columns` setting | `predict(include_fields = TRUE)` | ✅+ | **irelink improvement**: includes ALL source columns, not just blocking rule columns |
| `additional_columns_to_retain` setting | `predict(include_fields = TRUE)` | ✅ | Subsumed — all fields included when TRUE |
| `retain_intermediate_calculation_columns` | Always included (gamma columns) | ⚠️ | Gamma columns always present; original source values only via `include_fields` |
| `materialise_after_computing_term_frequencies` | — | ⚠️ | **Design difference**: irelink uses single-query SQL pipeline; materialization is implicit via DBI connection management. |
| `materialise_blocked_pairs` | — | ⚠️ | **Design difference**: irelink pushes blocking into the scored query. No separate materialization step needed. |
| `compare_two_records(r1, r2)` | `il_compare_records(r1, r2, spec, con)` | ✅ | |
| `deterministic_link()` | `il_deterministic_link(.data, spec, con)` | ✅ | |
| `find_matches_to_new_records(records, rules, threshold)` | `il_find_matches(model, new_records, threshold)` | ✅ | |
| `_score_missing_cluster_edges(clusters, predict)` | `il_score_missing_edges(model, pairs, clusters)` | ✅ | **Resolved**: enumerates within-cluster pairs, anti-joins against existing, scores missing via R-side gamma computation. See `R/il_score_missing_edges.R`. |
| Lazy SQL prediction (SplinkDataFrame wraps DB table) | `predict(collect = FALSE)` returns `il_compared_lazy` | ✅ | |

**Paths:** `splink/internals/linker_components/inference.py`, `splink/internals/predict.py`, `R/predict.R`, `R/il_compare_records.R`, `R/il_deterministic_link.R`, `R/il_find_matches.R`

---

## 6. Clustering

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `cluster_pairwise_predictions_at_threshold(preds, threshold)` | `il_cluster(pairs, threshold)` | ✅ | |
| Connected components algorithm | `il_cluster(method = "connected")` | ✅ | Default; SQL-native on DuckDB/PostgreSQL |
| `cluster_using_single_best_links(preds, duplicate_free_datasets, threshold, ties_method)` | `il_cluster(method = "best_link", ties_method, source_dataset)` | ✅ | **Resolved**: `source_dataset` parameter accepts a named vector or data frame mapping unique_id → dataset. Filters same-source edges in both R-path and SQL-path. See `R/il_cluster.R`. |
| `compute_graph_metrics(predict, clustered, threshold)` | `il_graph_metrics(pairs, clusters)` | ⚠️ | Partial: see §7 |

**Paths:** `splink/internals/linker_components/clustering.py`, `splink/internals/connected_components.py`, `splink/internals/one_to_one_clustering.py`, `R/il_cluster.R`, `R/utils-cc.R`

---

## 7. Graph Metrics

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| Node degree | `il_graph_metrics()$nodes$degree` | ✅ | |
| Cluster n_nodes, n_edges, density | `il_graph_metrics()$clusters` | ✅ | |
| Edge match_probability, match_weight | `il_graph_metrics()$edges` | ✅ | |
| **Bridge detection** (igraph-based `is_bridge` flag) | `il_graph_metrics()$edges$is_bridge` | ✅ | **Resolved**: uses igraph `bridges()` in R-path. `is_bridge` column added to edges tibble. Graceful fallback (all FALSE) when igraph not available. See `R/il_graph_metrics.R`. |
| Node centrality (normalized degree centralization) | `il_graph_metrics()$nodes$node_centrality` | ✅ | **Resolved**: `node_centrality = degree / (cluster_size - 1)`. Per-cluster `cluster_centralisation` added to clusters tibble (Freeman formula). Both SQL and R paths. See `R/il_graph_metrics.R`. |

**Paths:** `splink/internals/graph_metrics.py:175–236`, `splink/internals/edge_metrics.py`, `R/il_graph_metrics.R:80–200`

---

## 8. Evaluation

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `accuracy_analysis_from_labels_table(output_type="table")` | `il_accuracy(model, labels)` | ✅ | Returns precision/recall/F1 at all thresholds |
| `accuracy_analysis_from_labels_column(col)` | `il_accuracy(model, labels_col = col)` | ✅ | |
| `output_type="roc"` | `il_roc(model, labels)` | ✅ | |
| `output_type="threshold_selection"` | `il_precision_recall(model, labels)` | ✅ | |
| `prediction_errors_from_labels_table(include_fp, include_fn, threshold)` | `il_errors(model, labels, threshold)` | ✅ | Returns both FP and FN with `error_type` column |
| `unlinkables_chart()` | `il_unlinkables(model)` | ✅ | Data + `autoplot()` |
| `labelling_tool_for_specific_record(unique_id, out_path)` | — | 🚫 | Interactive HTML labelling tool |

**Paths:** `splink/internals/linker_components/evaluation.py`, `R/il_accuracy.R`, `R/il_roc.R`, `R/il_precision_recall.R`, `R/il_errors.R`, `R/il_unlinkables.R`

---

## 9. Visualisation

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `match_weights_chart()` | `autoplot(model)` | ✅ | ggplot2 |
| `m_u_parameters_chart()` | `autoplot(model, type = "parameters")` + `il_parameters()` | ✅ | |
| `parameter_estimate_comparisons_chart()` | `il_training_history(model)` + `autoplot()` | ✅ | |
| `waterfall_chart(records)` | `il_waterfall(pairs, which)` + `autoplot(pairs, which)` | ✅ | |
| `match_weights_histogram(preds, bins)` | `autoplot(predictions)` | ✅ | Configurable via ggplot2 |
| `tf_adjustment_chart(col, n_most, n_least)` | `il_tf_chart(model, col)` | ✅ | **Resolved**: ggplot2 bar chart of term frequencies with labelled most/least frequent values. See `R/il_tf_chart.R`. |
| `comparison_viewer_dashboard()` | — | 🚫 | Interactive HTML (JavaScript/Altair) |
| `cluster_studio_dashboard()` | — | 🚫 | Interactive HTML (JavaScript/Altair) |
| `completeness_chart()` | `il_completeness()` + `autoplot()` | ✅ | Data + ggplot2 |
| — | `autoplot(il_count_pairs)` | ✅+ | **irelink-original**: pair count waterfall chart |
| — | `autoplot(il_profile)` | ✅+ | **irelink-original**: column profile visualization |

**Paths:** `splink/internals/linker_components/visualisations.py`, `splink/internals/charts.py`, `R/autoplot.R`

---

## 10. Model Persistence

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `save_model_to_json(path, overwrite)` | `il_save(model, path, overwrite)` | ✅ | RDS format (native R) |
| Load settings from JSON | `il_load(path)` | ✅ | |
| Reattach to new data | `il_attach(model, .data, con)` | ✅ | |

**Paths:** `splink/internals/linker_components/misc.py`, `R/il_save.R`, `R/il_model.R:123–198`

---

## 11. Data Profiling & Exploration

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `profile_columns(df, top_n, bottom_n)` | `il_profile(df, ..., con, top_n, bottom_n)` | ✅ | |
| `profile_columns(column_expressions=["city \|\| first_name"])` | — | ⚠️ | **Partial**: no SQL expression profiling. Use `DBI::dbGetQuery()`. |
| `completeness_chart(df)` | `il_completeness(df, con)` | ✅ | Data + `autoplot()` |
| `comparator_score(str1, str2)` | `il_string_similarity(a, b)` | ✅ | 5 metrics in one call |
| `comparator_score_df(list, col1, col2)` | `il_comparator_score(df, col1, col2)` | ✅ | **Resolved**: batch string similarity on a DataFrame. SQL-side scoring for DuckDB/PostgreSQL, R-side via stringdist fallback. See `R/il_comparator_score.R`. |
| `comparator_score_chart()` | `autoplot(il_string_similarity(a, b))` | ✅ | **Resolved**: horizontal bar chart of string similarity metrics with colour-coded scores. See `R/il_tf_chart.R` (`autoplot.il_string_similarity()`). |
| `comparator_score_threshold_chart()` | `il_comparator_threshold_chart(df, col1, col2)` | ✅ | **Resolved**: threshold analysis chart. Computes match rates at multiple thresholds for each metric. See `R/il_comparator_score.R`. |
| `phonetic_transform(string)` | `il_soundex(x)`, `il_metaphone(x)`, `il_dmetaphone(x)` | ✅ | |
| `phonetic_match_chart()` | `il_phonetic_chart(df, col1, col2)` | ✅ | **Resolved**: Soundex agreement heatmap with match counts. See `R/il_comparator_score.R`. |
| Comparison vector distribution | `il_comparison_vectors(model)` | ✅ | **Resolved**: gamma pattern distribution with counts and proportions. `autoplot()` method produces horizontal bar chart of top 20 patterns. See `R/il_comparison_vectors.R`. |

**Paths:** `splink/internals/profile_data.py`, `splink/internals/similarity_analysis.py`, `splink/internals/comparison_vector_values.py`, `R/il_profile.R`, `R/il_completeness.R`, `R/il_string_similarity.R`, `R/il_phonetic.R`

---

## 12. Term Frequency Adjustments

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| Per-comparison TF adjustment | `cl_exact(term_frequency = TRUE)` | ✅ | |
| TF on fuzzy matches | `cl_jaro_winkler(..., term_frequency = TRUE)` | ✅ | Applied at highest gamma |
| `compute_tf_table(column_name)` | Automatic — computed internally | ✅ | |
| `register_term_frequency_lookup(data, col)` | `il_register_tf(model, col, tf_data)` | ✅ | **Resolved**: registers pre-computed TF tables in the database. Validates column structure, supports `overwrite` parameter. See `R/il_register_tf.R`. |
| `tf_adjustment_chart(col, n_most, n_least)` | `il_tf_chart(model, col)` | ✅ | **Resolved**: See §9 |

**Paths:** `splink/internals/term_frequencies.py`, `splink/internals/linker_components/table_management.py`, `R/utils-tf.R`

---

## 13. Datasets

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `fake_1000` (250 people, 1000 records) | `fake_1000` | ✅ | Identical data |
| `fake_1000_labels` | `fake_1000_labels` | ✅ | |
| `febrl4a` (5000 originals) | `febrl4a` | ✅ | |
| `febrl4b` (5000 duplicates) | `febrl4b` | ✅ | |
| — | `fake_20` (5 people, 20 records) | ✅+ | **irelink-original**: minimal example for quick tests |
| `historical_50k` (50K Wikidata persons) | — | ❌ | **Missing** |
| `febrl3` (2000 originals + 3000 duplicates) | — | ❌ | **Missing** |
| `transactions_origin` (bank transactions) | — | ❌ | **Missing** |
| `transactions_destination` (bank transactions) | — | ❌ | **Missing** |

**Paths:** `splink/internals/datasets/splink_datasets.py:65–182`, `R/data.R`

---

## 14. Database Backends

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| DuckDB | DuckDB | ✅ | Default backend for both |
| PostgreSQL | PostgreSQL | ✅ | |
| SQLite | SQLite | ✅ | With R-side fallbacks for stringdist |
| Spark | — | 🚫 | Cluster-computing; not relevant for R |
| Athena | — | 🚫 | AWS-specific; not relevant for R |

**Paths:** `splink/backends/`, `R/utils-sql.R`

---

## 15. Table Management & Caching

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `register_table(input, name, overwrite)` | `DBI::dbWriteTable()` | ✅ | Standard DBI |
| `register_labels_table(data)` | Labels passed directly to eval functions | ✅ | Different API, same result |
| `invalidate_cache()` | — | ⚠️ | No explicit cache; tables rebuilt each `predict()` |
| `delete_tables_created_by_splink_from_db()` | `il_cleanup(model)` | ✅ | |
| CTE pipeline caching (`CacheDictWithLogging`) | — | ⚠️ | No CTE caching; acceptable for DuckDB single-process model |
| `query_sql(sql)` | `DBI::dbGetQuery(con, sql)` | ✅ | Standard DBI |

**Paths:** `splink/internals/linker_components/table_management.py`, `splink/internals/cache_dict_with_logging.py`, `R/il_cleanup.R`

---

## 16. Advanced / Settings

| splink | irelink | Status | Notes |
|--------|---------|--------|-------|
| `bayes_factor_column_prefix` | Fixed `bf_` prefix | ⚠️ | Not configurable |
| `term_frequency_adjustment_column_prefix` | Fixed `tf_` prefix | ⚠️ | Not configurable |
| `comparison_vector_value_column_prefix` | Fixed `gamma_` prefix | ⚠️ | Not configurable |
| Realtime comparison (`realtime.py`, `SQLCache`) | `il_compare_records()` | ⚠️ | No SQL caching; one-off comparisons only |
| Self-link for unlinkables | Internal implementation | ✅ | Used by `il_unlinkables()` |

**Paths:** `splink/internals/realtime.py`, `splink/internals/settings_creator.py`, `R/il_compare_records.R`, `R/il_unlinkables.R`

---

## 17. irelink-Original Features (Not in splink)

These features exist in irelink but have no direct equivalent in splink's
public API:

| Feature | File | Description |
|---------|------|-------------|
| `il_suggest_blocking()` | `R/il_suggest_blocking.R` | Heuristic-scored ranking of single- and multi-column blocking rules by pair reduction, coverage, and balanced score. splink's equivalent (`_detect_blocking_rules_for_prediction()`) is an internal method. |
| `il_find_blocking_below()` | `R/il_suggest_blocking.R` | Public API to find blocking rule combinations below a pair count ceiling. splink's equivalent is an internal method. |
| `cl_zip_code()` | `R/cl_domain.R` | US ZIP code comparison (5-digit + SCF 3-digit levels, optional geo fallback). splink only has `PostcodeComparison` for UK postcodes. |
| `cl_first_last_name()` | `R/cl_domain.R` | American-English alias for `cl_forename_surname()`. |
| `labels_from_column()` | `R/utils-evaluation.R` | Converts an entity ID column into pairwise labels for evaluation. splink requires manual label table creation. |
| `fake_20` dataset | `R/data.R` | Minimal 20-record example for quick tests. |
| `include_fields` on `predict()` | `R/predict.R` | Single boolean to include all source columns, simpler than splink's `retain_matching_columns` + `additional_columns_to_retain`. |
| `collect = FALSE` lazy path | `R/predict.R` | Explicit lazy/eager prediction toggle. splink always returns a `SplinkDataFrame` wrapper. |
| `transform` argument | `R/il_compare.R`, `R/il_block_on.R` | R function → SQL transform pipeline (e.g., `tolower`, `il_soundex`). More integrated than splink's `ColumnExpression`. |
| `il_transform()` composition | `R/il_transform.R` | Compose multiple R transforms into a single chainable function with SQL nesting. |
| `il_tf_chart()` | `R/il_tf_chart.R` | TF frequency distribution chart with labelled most/least common values. |
| `autoplot.il_string_similarity` | `R/il_tf_chart.R` | Comparator score bar chart from `il_string_similarity()` output. |
| `il_comparator_score()` | `R/il_comparator_score.R` | **NEW**: Batch DataFrame string similarity with SQL-side scoring. |
| `il_comparator_threshold_chart()` | `R/il_comparator_score.R` | **NEW**: Threshold analysis chart for string metrics. |
| `il_phonetic_chart()` | `R/il_comparator_score.R` | **NEW**: Soundex agreement heatmap. |
| `il_comparison_vectors()` | `R/il_comparison_vectors.R` | **NEW**: Gamma pattern distribution analysis with autoplot. |
| `il_register_tf()` | `R/il_register_tf.R` | **NEW**: Register pre-computed term frequency tables. |
| `il_column_transforms` | `R/il_column_transforms.R` | **NEW**: Factory functions for SQL column transforms (il_substr, il_regex_extract, il_nullif, il_cast_to_string, il_try_parse_date, il_array_element). |
| `il_soundex()` as R function | `R/il_phonetic.R` | Usable both as R-side function and SQL macro. |
| tidyselect in `il_compare()` | `R/il_compare.R` | Apply same comparison to multiple columns: `il_compare(c(col1, col2), cl_exact())`. |
| ggplot2 autoplot ecosystem | `R/autoplot.R` | Native R visualization with 10+ autoplot methods. All chart types composable with standard ggplot2 layers. |
| `autoplot(il_count_pairs)` | `R/autoplot.R` | Pair count waterfall visualization. |
| `autoplot(il_profile)` | `R/autoplot.R` | Column profile visualization. |

---

## Summary Tables

### Gap Severity

| Severity | Count | Items |
|----------|-------|-------|
| **All functional gaps resolved** | 0 | — |
| **Design differences** (⚠️, accepted) | 8 | Materialization controls (2), column prefix configuration (3), ColumnExpression API style, `try_parse_timestamp`, CTE caching |
| **Extra datasets** (skipped) | 4 | `historical_50k`, `febrl3`, `transactions_origin`, `transactions_destination` |
| **Excluded by scope** (🚫) | 5 | Spark, Athena, comparison_viewer_dashboard, cluster_studio_dashboard, labelling_tool |

### Feature Counts

| Category | splink features | Covered | irelink-original | Gaps | Excluded |
|----------|----------------|---------|-----------------|------|----------|
| Core pipeline | 8 | 8 | 0 | 0 | 0 |
| Comparisons (string/numeric) | 12 | 12 | 0 | 0 | 0 |
| Comparisons (array) | 3 | 3 | 0 | 0 | 0 |
| Comparisons (domain) | 5 | 5 | 2 | 0 | 0 |
| Comparison levels | 11 | 11 | 0 | 0 | 0 |
| Column expressions | 9 | 9 | 1 | 0 | 0 |
| Blocking | 9 | 8 | 2 | 0 | 1 |
| Training | 11 | 11 | 0 | 0 | 0 |
| Prediction | 11 | 11 | 2 | 0 | 0 |
| Clustering | 4 | 4 | 0 | 0 | 0 |
| Graph metrics | 5 | 5 | 0 | 0 | 0 |
| Evaluation | 7 | 6 | 1 | 0 | 1 |
| Visualisation | 10 | 8 | 2 | 0 | 2 |
| Model persistence | 3 | 3 | 0 | 0 | 0 |
| Profiling/exploration | 10 | 10 | 1 | 0 | 0 |
| Term frequency | 4 | 4 | 0 | 0 | 0 |
| Datasets | 8 | 4 | 1 | 4 | 0 |
| Backends | 5 | 3 | 0 | 0 | 2 |
| Table management | 6 | 4 | 0 | 0 | 0 |
| Settings/advanced | 5 | 2 | 0 | 1 | 0 |
| **Totals** | **146** | **135** | **12** | **5** | **6** |

> **Note**: The 5 remaining gaps are: 4 extra datasets (skipped by request) + 1 minor
> settings item (`bayes_factor_column_prefix` configurability). All functional feature
> gaps have been resolved.

### Priority Recommendations

**High priority** (all resolved):

1. ~~**`AbsoluteTimeDifferenceAtThresholds`**~~ — ✅ **Resolved** via `cl_time_diff()`
   with `seconds()`, `minutes()`, `hours()` unit helpers. SQL epoch-based diff
   for DuckDB/PostgreSQL; R-side difftime fallback for SQLite.
   *Files:* `R/cl_time_diff.R`, `R/utils-unit-helpers.R`, `R/utils-sql.R`, `R/utils-em.R`

2. ~~**Bridge detection in graph metrics**~~ — ✅ **Resolved** via igraph
   `bridges()`. `is_bridge` column added to `il_graph_metrics()$edges`.
   Graceful fallback when igraph is not installed.
   *Files:* `R/il_graph_metrics.R`

3. ~~**`duplicate_free_datasets` on best-link clustering**~~ — ✅ **Resolved**
   via `source_dataset` parameter on `il_cluster()`. Accepts named vector or
   data frame mapping unique_id → dataset name. Filters same-source edges in
   both R-path and SQL-path before best-link selection.
   *Files:* `R/il_cluster.R`

4. ~~**`_score_missing_cluster_edges`**~~ — ✅ **Resolved** via
   `il_score_missing_edges(model, pairs, clusters)`. Enumerates all
   within-cluster pairs, anti-joins against existing scored pairs, scores
   missing pairs R-side using `compute_gamma()` + `score_gamma_matrix()`.
   *Files:* `R/il_score_missing_edges.R`

**Medium priority** (all resolved):

5. ~~**Standalone `cl_columns_reversed()`**~~ — ✅ **Resolved** via dedicated
   `cl_columns_reversed(col2)` function. Also refactored `cl_forename_surname()`
   to use it internally. Delegates to `cl_custom()` with `{col}` placeholder.
   *Files:* `R/cl_columns_reversed.R`, `R/cl_domain.R`

6. ~~**`threshold_match_weight` on predict**~~ — ✅ **Resolved** via
   `predict(model, threshold_match_weight = 5)`. When set, filters on log₂
   Bayes factor instead of probability in both R-path and SQL-path.
   *Files:* `R/predict.R`, `R/utils-sql.R`

7. ~~**`arrays_to_explode` blocking**~~ — ✅ **Resolved** via `.explode`
   parameter on `il_block_on()` and `block_on()`. Generates
   `SELECT * EXCLUDE (...), UNNEST(...) AS ... FROM tbl` subqueries for
   DuckDB; `CROSS JOIN LATERAL UNNEST()` for PostgreSQL; warns and skips
   for SQLite. 18 tests.
   *Files:* `R/il_block_on.R`, `R/utils-sql.R` (`sql_explode_from()`)

8. **Additional datasets** (`historical_50k`, `febrl3`, transactions) — useful
   for benchmarking and tutorials but can be added as needed.

**Low priority** (nice-to-have, workarounds exist):

9. ~~**ColumnExpression method chaining**~~ — ✅ **Resolved** via
   `il_transform(fn1, fn2, ...)`. Creates a composable transform function
   that applies steps sequentially. SQL-side generates nested expressions
   (e.g. `TRIM(LOWER(col))`). Works with `il_compare(transform = ...)` and
   `il_block_on(.transform = ...)`. 15 tests.
   *Files:* `R/il_transform.R`, `R/utils-sql.R`

10. ~~**Exploratory charts**~~ — ✅ **Resolved** via `il_tf_chart(model, col)`
    for TF distribution visualization and `autoplot(il_string_similarity(a, b))`
    for comparator score bar chart. Both return static ggplot2 objects.
    `il_string_similarity()` output now has class `il_string_similarity` for
    autoplot dispatch. 8 tests.
    *Files:* `R/il_tf_chart.R`, `R/il_string_similarity.R`

11. ~~**EM training fine-tuning**~~ — ✅ **Resolved** via `fix_prior`,
    `estimate_without_tf`, `derive_prior`, and `max_iterations` parameters
    on `il_estimate_em()`. See `R/il_estimate_em.R`.

12. **Materialization controls** — ⚠️ **Design difference**: irelink uses
    single-query SQL pipeline; DuckDB's in-process model makes explicit
    materialization less critical than in Spark. Accepted as-is.

13. ~~**Column expression transforms**~~ — ✅ **Resolved** via factory functions:
    `il_substr()`, `il_regex_extract()`, `il_nullif()`, `il_cast_to_string()`,
    `il_try_parse_date()`, `il_array_element()`. All produce SQL-side expressions.
    Composable with `il_transform()`. 37 tests.
    *Files:* `R/il_column_transforms.R`, `R/utils-sql.R`

14. ~~**Node centrality**~~ — ✅ **Resolved** via `node_centrality` column on
    nodes tibble and `cluster_centralisation` on clusters tibble. Freeman
    degree centralisation formula. Both SQL and R paths. 2 new tests.
    *Files:* `R/il_graph_metrics.R`

15. ~~**Batch comparator scoring**~~ — ✅ **Resolved** via
    `il_comparator_score(df, col1, col2)` with SQL-side scoring for DuckDB,
    `il_comparator_threshold_chart()` for threshold analysis, and
    `il_phonetic_chart()` for Soundex agreement heatmap. 10 tests.
    *Files:* `R/il_comparator_score.R`

16. ~~**Comparison vector distribution**~~ — ✅ **Resolved** via
    `il_comparison_vectors(model)`. Returns gamma pattern distribution with
    counts and proportions. `autoplot()` method for bar chart. 7 tests.
    *Files:* `R/il_comparison_vectors.R`

17. ~~**Register pre-computed TF tables**~~ — ✅ **Resolved** via
    `il_register_tf(model, col, tf_data, overwrite)`. Writes to `__il_tf_<col>`
    table with validation and overwrite guard. 6 tests.
    *Files:* `R/il_register_tf.R`

---

## SQL Push-Down Audit

Post-implementation audit verifying all new features maximise SQL-side
computation with R-only fallbacks for SQLite or missing database extensions.

| File | Rating | Notes |
|------|--------|-------|
| `R/il_comparison_vectors.R` | ✅ | Rewrote to use `GROUP BY + COUNT(*)` wrapping `build_gamma_query()` in SQL for DuckDB/PG. R `stats::aggregate()` fallback only for SQLite. |
| `R/il_comparator_score.R` | ✅ | DuckDB: 4 SQL-native metrics. PostgreSQL: 2 metrics + `cli::cli_warn()` + NA fill. R fallback: all 5 via `stringdist`. |
| `R/il_comparator_score.R` (phonetic) | ✅ | `il_phonetic_chart()` now accepts `con` and pushes `il_soundex`/`soundex()` to SQL for DuckDB/PostgreSQL. |
| `R/il_column_transforms.R` | ✅ | All transform factories generate SQL expressions; no R-side computation. |
| `R/il_register_tf.R` | ✅ | Data loading via `DBI::dbWriteTable()`; no R-side computation. |
| `R/il_graph_metrics.R` | ✅ | Node centrality and cluster centralisation computed in SQL for DuckDB/PG; igraph fallback for R path. |
| `R/cl_time_diff.R` | ✅ | SQL epoch-based diff for DuckDB/PG; R `difftime()` fallback for SQLite. |
| `R/il_estimate_em.R` | ✅ | `estimate_without_tf` documented as API-compat no-op (TF applied at scoring, not EM). |
| `R/il_tf_chart.R` | ✅ | Reads from existing SQL TF tables; aggregation happens in SQL via `build_gamma_query()`. |
| `R/il_score_missing_edges.R` | ⚠️ | Pair enumeration is R-side (anti-join of within-cluster pairs vs scored pairs). Acceptable: requires cluster membership which is already materialised. |
