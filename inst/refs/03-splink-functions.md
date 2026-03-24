# Splink Function and Class Catalog

> Reference for irelink translation.
> Organized by functional category; thin one-liners and Python-specific
> helpers are omitted. "Visibility" marks items as **public** (user-facing)
> or **internal** (implementation detail).

---

## 1 Public API Surface

Everything re-exported from `splink/__init__.py`. These are the items
users interact with directly when writing linkage scripts.

| Name | Kind | Description | File |
|------|------|-------------|------|
| `Linker` | class | Main orchestrator: holds model, data, and sub-API components | `internals/linker.py` |
| `SettingsCreator` | class | Dialect-agnostic builder that produces a `Settings` object once a backend is chosen | `internals/settings_creator.py` |
| `ColumnExpression` | class | Chainable column transformer applied before comparison (`.lower()`, `.substr()`, `.regex_extract()`, etc.) | `internals/column_expression.py` |
| `DuckDBAPI` | class | Database back-end for DuckDB (lazy-loaded) | `internals/duckdb/database_api.py` |
| `SparkAPI` | class | Database back-end for Spark (lazy-loaded) | `internals/spark/database_api.py` |
| `block_on` | function | Shorthand to build equality-based blocking rules on one or more columns | `internals/blocking_rule_library.py` |
| `splink_datasets` | singleton | Accessor for bundled demo datasets (`fake_1000`, `historical_50k`, `febrl3`, etc.) | `internals/datasets/splink_datasets.py` |

---

## 2 Linker Sub-APIs

The `Linker` exposes seven component objects as attributes. Each groups
a set of related public methods.

### 2.1 Inference (`linker.inference`)

| Method | Description | File |
|--------|-------------|------|
| `predict()` | Score all blocked pairs using trained model parameters; supports probability and weight thresholds | `linker_components/inference.py` |
| `deterministic_link()` | Return exact-match pairs from blocking rules without probabilistic scoring | `linker_components/inference.py` |
| `find_matches_to_new_records()` | Search existing data for matches to one or more new records | `linker_components/inference.py` |
| `compare_two_records()` | Score a single pairwise comparison (or cartesian product when given multiple rows) | `linker_components/inference.py` |

Internal helpers in the same file: `_score_missing_cluster_edges()`.

### 2.2 Training (`linker.training`)

| Method | Description | File |
|--------|-------------|------|
| `estimate_probability_two_random_records_match()` | Estimate the global match prior using deterministic rules and a recall estimate | `linker_components/training.py` |
| `estimate_u_using_random_sampling()` | Estimate u (non-match) probabilities from randomly sampled pairs | `linker_components/training.py` |
| `estimate_parameters_using_expectation_maximisation()` | Run EM iterations under a blocking rule to learn m and/or u parameters | `linker_components/training.py` |
| `estimate_m_from_pairwise_labels()` | Learn m (match) probabilities from a table of labelled record pairs | `linker_components/training.py` |
| `estimate_m_from_label_column()` | Learn m probabilities from a ground-truth identifier column (e.g. SSN) | `linker_components/training.py` |

### 2.3 Clustering (`linker.clustering`)

| Method | Description | File |
|--------|-------------|------|
| `cluster_pairwise_predictions_at_threshold()` | Apply connected-components to group predictions above a threshold | `linker_components/clustering.py` |
| `cluster_using_single_best_links()` | Cluster with the constraint that each source dataset contributes at most one record per cluster | `linker_components/clustering.py` |
| `compute_graph_metrics()` | Return node-, edge-, and cluster-level graph metrics (degree, density, bridges) | `linker_components/clustering.py` |

Internal helpers: `_compute_metrics_nodes()`, `_compute_metrics_edges()`,
`_compute_metrics_clusters()`.

### 2.4 Evaluation (`linker.evaluation`)

| Method | Description | File |
|--------|-------------|------|
| `prediction_errors_from_labels_table()` | Find false positives/negatives by comparing predictions against labelled pairs | `linker_components/evaluation.py` |
| `prediction_errors_from_labels_column()` | Same, but driven by a ground-truth identifier column | `linker_components/evaluation.py` |
| `accuracy_analysis_from_labels_table()` | Produce accuracy charts or tables (ROC, precision-recall, threshold picker) from labelled pairs | `linker_components/evaluation.py` |
| `accuracy_analysis_from_labels_column()` | Same, driven by a label column | `linker_components/evaluation.py` |
| `unlinkables_chart()` | Chart showing the proportion of records that cannot be linked at each threshold | `linker_components/evaluation.py` |
| `labelling_tool_for_specific_record()` | Generate a standalone HTML labelling dashboard for one record's candidate matches | `linker_components/evaluation.py` |

### 2.5 Visualizations (`linker.visualisations`)

| Method | Description | File |
|--------|-------------|------|
| `match_weights_chart()` | Bar chart of partial match weights per comparison level | `linker_components/visualisations.py` |
| `m_u_parameters_chart()` | Chart of m and u parameter values across all comparisons | `linker_components/visualisations.py` |
| `match_weights_histogram()` | Histogram of match-weight distribution from prediction results | `linker_components/visualisations.py` |
| `parameter_estimate_comparisons_chart()` | Compare parameter estimates across different training runs | `linker_components/visualisations.py` |
| `tf_adjustment_chart()` | Show how term-frequency adjustments shift match weights for a given comparison | `linker_components/visualisations.py` |
| `waterfall_chart()` | Decompose a pairwise comparison into its component match-weight contributions | `linker_components/visualisations.py` |
| `comparison_viewer_dashboard()` | Interactive HTML dashboard with comparison vectors and example records | `linker_components/visualisations.py` |
| `cluster_studio_dashboard()` | Interactive HTML dashboard for exploring clustered records | `linker_components/visualisations.py` |

### 2.6 Table Management (`linker.table_management`)

| Method | Description | File |
|--------|-------------|------|
| `register_table()` | Register an external data object (dict, data frame, etc.) as a backend table | `linker_components/table_management.py` |
| `compute_tf_table()` | Compute and persist a term-frequency lookup table for one column | `linker_components/table_management.py` |
| `register_term_frequency_lookup()` | Supply a pre-computed term-frequency table | `linker_components/table_management.py` |
| `register_table_input_nodes_concat_with_tf()` | Supply a pre-computed concatenated-input-with-TF table | `linker_components/table_management.py` |
| `register_table_predict()` | Supply a pre-computed prediction table | `linker_components/table_management.py` |
| `register_labels_table()` | Register a table of pairwise labels for evaluation | `linker_components/table_management.py` |
| `invalidate_cache()` | Clear the result cache so intermediate tables are recomputed | `linker_components/table_management.py` |
| `delete_tables_created_by_splink_from_db()` | Remove all temporary tables from the database | `linker_components/table_management.py` |

### 2.7 Misc (`linker.misc`)

| Method | Description | File |
|--------|-------------|------|
| `save_model_to_json()` | Serialize trained model configuration and parameters to JSON | `linker_components/misc.py` |
| `query_sql()` | Run raw SQL against the backend and return results as a data frame or Splink object | `linker_components/misc.py` |

---

## 3 Settings and Configuration

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `Settings` | class | internal | Root settings object: holds comparisons, blocking rules, prior, column metadata, and trained parameters | `settings.py` |
| `SettingsCreator` | class | public | Dialect-free builder; call `.get_settings(dialect)` to produce a bound `Settings` | `settings_creator.py` |
| `ColumnInfoSettings` | dataclass | internal | Column-naming configuration: prefixes, unique-ID column, SQL dialect | `settings.py` |
| `TrainingSettings` | dataclass | internal | EM convergence threshold and max-iteration cap | `settings.py` |
| `CoreModelSettings` | dataclass | internal | Comparisons list plus the global match prior probability | `settings.py` |
| `default_value_from_schema()` | function | internal | Look up a default value from the settings JSON schema | `default_from_jsonschema.py` |
| `get_schema()` | function | internal | Load the full settings JSON schema (cached) | `validate_jsonschema.py` |

### 3.1 Settings Validation

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `InvalidColumnsLogger` | class | internal | Validate that all columns referenced in settings exist in the input data | `settings_validation/log_invalid_columns.py` |
| `SettingsColumnCleaner` | class | internal | Extract and normalize column names from settings and input tables for validation | `settings_validation/settings_column_cleaner.py` |
| `InvalidColumnsLogGenerator` | named tuple | internal | Container for validation-error info with formatted message generation | `settings_validation/settings_validation_log_strings.py` |
| `validate_table_names()` | function | internal | Check that column references use only `l` or `r` table prefixes | `settings_validation/log_invalid_columns.py` |
| `validate_column_suffixes()` | function | internal | Check that column references end with `_l` or `_r` | `settings_validation/log_invalid_columns.py` |
| `check_for_missing_or_invalid_columns_in_sql_strings()` | function | internal | Parse SQL strings and verify every referenced column exists in the inputs | `settings_validation/log_invalid_columns.py` |

---

## 4 Blocking System

### 4.1 Core Blocking Engine

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `BlockingRule` | class | internal | Represents a single blocking condition; generates the blocked-pairs SQL including deduplication against preceding rules | `blocking.py` |
| `SaltedBlockingRule` | class | internal | Extends `BlockingRule` with random-salt partitioning for parallelism | `blocking.py` |
| `ExplodingBlockingRule` | class | internal | Extends `BlockingRule` to handle array columns by exploding them first | `blocking.py` |
| `block_using_rules_sqls()` | function | internal | Produce the full SQL pipeline that applies a sequence of blocking rules with incremental deduplication | `blocking.py` |
| `blocking_rule_to_obj()` | function | internal | Normalize a dict or string into a `BlockingRule` subclass | `blocking.py` |

### 4.2 Blocking Rule Builders (user-facing)

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `BlockingRuleCreator` | ABC | public | Abstract base for blocking-rule creators; subclasses define `create_sql()` | `blocking_rule_creator.py` |
| `ExactMatchRule` | class | public | Blocking rule requiring exact equality on one column | `blocking_rule_library.py` |
| `CustomRule` | class | public | Blocking rule from arbitrary user SQL | `blocking_rule_library.py` |
| `And` | class | public | Combine blocking rules with logical AND | `blocking_rule_library.py` |
| `Or` | class | public | Combine blocking rules with logical OR | `blocking_rule_library.py` |
| `Not` | class | public | Negate a blocking rule | `blocking_rule_library.py` |
| `block_on()` | function | public | Shorthand for equality blocking on one or more columns | `blocking_rule_library.py` |

### 4.3 Blocking Analysis and Optimization

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `count_comparisons_from_blocking_rule()` | function | public | Count the pairwise comparisons a single blocking rule would generate | `blocking_analysis.py` |
| `cumulative_comparisons_to_be_scored_from_blocking_rules_data()` | function | public | Data frame of cumulative comparison counts as rules are added sequentially | `blocking_analysis.py` |
| `cumulative_comparisons_to_be_scored_from_blocking_rules_chart()` | function | public | Chart of the above | `blocking_analysis.py` |
| `n_largest_blocks()` | function | public | Identify the n blocking-key values that produce the most comparisons | `blocking_analysis.py` |
| `find_blocking_rules_below_threshold_comparison_count()` | function | public | Recursive search for column combinations whose blocking rules stay under a comparison-count ceiling | `find_brs_with_comparison_counts_below_threshold.py` |
| `suggest_blocking_rules()` | function | public | Heuristic optimizer that balances comparison count against field coverage | `optimise_cost_of_brs.py` |
| `block_from_labels()` | function | public | Build blocked pairs from a manually curated labels table | `block_from_labels.py` |
| `calculate_field_freedom_cost()` | function | internal | Cost metric based on how many fields are allowed to vary | `cost_of_blocking_rules.py` |
| `calculate_cost_of_combination_of_brs()` | function | internal | Weighted cost for a combination of blocking rules | `cost_of_blocking_rules.py` |

---

## 5 Comparison System

### 5.1 Core Comparison Classes

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `Comparison` | class | internal | A multi-level comparison on one or more columns; assembles the `CASE WHEN ... END` SQL and stores m/u probabilities | `comparison.py` |
| `ComparisonLevel` | class | internal | A single gradation of similarity within a comparison; carries its SQL condition, chart label, and m/u values | `comparison_level.py` |
| `ComparisonCreator` | ABC | public | Abstract base for comparison builders; subclasses define `create_comparison_levels()` and `create_output_column_name()` | `comparison_creator.py` |
| `ComparisonLevelCreator` | ABC | public | Abstract base for level builders; subclasses define `create_sql()` and `create_label_for_charts()` | `comparison_level_creator.py` |

### 5.2 Comparison Level Library (individual levels)

All are `ComparisonLevelCreator` subclasses in
`comparison_level_library.py`. Every item is **public**.

| Name | Description |
|------|-------------|
| `NullLevel` | Captures pairs where one or both values are NULL |
| `ElseLevel` | Catch-all for pairs not matched by higher levels |
| `CustomLevel` | User-supplied SQL condition |
| `ExactMatchLevel` | Exact string equality, with optional term-frequency adjustment |
| `LiteralMatchLevel` | Match against a hard-coded literal value |
| `ColumnsReversedLevel` | Match when two columns swap values (e.g. first/last name reversal) |
| `LevenshteinLevel` | Levenshtein edit distance within a threshold |
| `DamerauLevenshteinLevel` | Damerau-Levenshtein distance (allows transpositions) |
| `JaroWinklerLevel` | Jaro-Winkler similarity above a threshold |
| `JaroLevel` | Jaro similarity above a threshold |
| `JaccardLevel` | Jaccard similarity above a threshold |
| `CosineSimilarityLevel` | Cosine similarity above a threshold |
| `DistanceFunctionLevel` | Arbitrary SQL distance function with a threshold |
| `AbsoluteTimeDifferenceLevel` | Absolute time difference within a metric-based threshold |
| `AbsoluteDateDifferenceLevel` | Absolute date difference within a threshold |
| `AbsoluteDifferenceLevel` | Numeric absolute difference within a threshold |
| `PercentageDifferenceLevel` | Numeric percentage difference within a threshold |
| `DistanceInKMLevel` | Great-circle geographic distance within a km threshold |
| `ArrayIntersectLevel` | Array intersection size above a minimum |
| `ArraySubsetLevel` | One array is a subset of another |
| `PairwiseStringDistanceFunctionLevel` | Best pairwise distance between elements of two arrays |

### 5.3 Comparison Level Composition

In `comparison_level_composition.py`; all **public**.

| Name | Description |
|------|-------------|
| `And` | Combine levels with logical AND |
| `Or` | Combine levels with logical OR |
| `Not` | Negate a level |

### 5.4 Comparison Library (pre-built multi-level comparisons)

All are `ComparisonCreator` subclasses in `comparison_library.py`.
Every item is **public**.

| Name | Description |
|------|-------------|
| `ExactMatch` | Two-level comparison: exact match or else |
| `LevenshteinAtThresholds` | Exact match plus Levenshtein levels at one or more distance thresholds |
| `DamerauLevenshteinAtThresholds` | Same pattern with Damerau-Levenshtein |
| `JaroAtThresholds` | Exact match plus Jaro similarity levels |
| `JaroWinklerAtThresholds` | Exact match plus Jaro-Winkler similarity levels |
| `JaccardAtThresholds` | Exact match plus Jaccard similarity levels |
| `CosineSimilarityAtThresholds` | Exact match plus cosine similarity levels |
| `DistanceFunctionAtThresholds` | Generic distance function at multiple thresholds |
| `AbsoluteTimeDifferenceAtThresholds` | Time differences at multiple thresholds |
| `AbsoluteDateDifferenceAtThresholds` | Date differences at multiple thresholds |
| `ArrayIntersectAtSizes` | Array intersection at multiple size thresholds |
| `DistanceInKMAtThresholds` | Geographic distance at multiple km thresholds |
| `CustomComparison` | User-defined levels with arbitrary SQL |
| `DateOfBirthComparison` | Pre-configured comparison tailored for date-of-birth columns |
| `NameComparison` | Pre-configured comparison tailored for name columns |
| `ForenameSurnameComparison` | Paired forename/surname comparison with cross-field swap detection |
| `EmailComparison` | Pre-configured comparison tailored for email addresses |
| `PostcodeComparison` | Pre-configured comparison for postcodes, with optional geographic fallback |
| `PairwiseStringDistanceFunctionAtThresholds` | Best pairwise distance between array elements at thresholds |

---

## 6 SQL Generation and Pipeline

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `CTEPipeline` | class | internal | Accumulates SQL snippets as named CTEs and emits a single `WITH ... SELECT` statement | `pipeline.py` |
| `CTE` | class | internal | A single common-table-expression node: SQL text plus an output name | `pipeline.py` |
| `InputColumn` | class | internal | Represents an input column with automatic quoting, `_l`/`_r` suffixing, and TF-column naming | `input_column.py` |
| `ColumnExpression` | class | public | Chainable, dialect-agnostic column transformer (`.lower()`, `.substr()`, `.regex_extract()`, `.nullif()`, `.try_parse_date()`, `.try_parse_timestamp()`, `.access_extreme_array_element()`) | `column_expression.py` |
| `SplinkDialect` | ABC | internal | Abstract dialect interface: declares function names for backend-specific SQL (Levenshtein, Jaro-Winkler, regex, array ops, etc.) | `dialects.py` |
| `DuckDBDialect` | class | internal | Concrete dialect for DuckDB | `dialects.py` |
| `get_columns_used_from_sql()` | function | internal | Use sqlglot to extract every column name from a SQL string | `parse_sql.py` |
| `parse_columns_in_sql()` | function | internal | Parse SQL and return sqlglot Column objects for further AST manipulation | `parse_sql.py` |
| `sqlglot_transform_sql()` | function | internal | Apply a transformation function to a sqlglot AST and return the result as SQL text | `sql_transform.py` |
| `move_l_r_table_prefix_to_column_suffix()` | function | internal | Rewrite `l.name` → `name_l` in blocking-rule SQL | `sql_transform.py` |
| `add_suffix_to_all_column_identifiers()` | function | internal | Append `_l` or `_r` to every column identifier in a SQL string | `sql_transform.py` |
| `add_table_to_all_column_identifiers()` | function | internal | Prefix every column identifier with a table name | `sql_transform.py` |
| `great_circle_distance_km_sql()` | function | internal | Emit the Haversine SQL formula for distance in km between lat/lon pairs | `comparison_level_sql.py` |
| `_composite_unique_id_from_nodes_sql()` | function | internal | Concatenate unique-ID columns into a single key for row identification | `unique_id_concat.py` |
| `_composite_unique_id_from_edges_sql()` | function | internal | Same, but with `_l`/`_r` suffixes for blocked pairs | `unique_id_concat.py` |
| `lower_id_to_left_hand_side()` | function | internal | Reorder `_l`/`_r` columns so the lower ID is always on the left | `lower_id_on_lhs.py` |

---

## 7 Training and EM

### 7.1 EM Algorithm

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `EMTrainingSession` | class | internal | Manages one EM training run: tracks parameter evolution, generates iteration charts | `em_training_session.py` |
| `expectation_maximisation()` | function | internal | Main EM loop: iterates E-step and M-step until convergence or max iterations | `expectation_maximisation.py` |
| `maximisation_step()` | function | internal | M-step: update m/u parameters from E-step probability estimates | `expectation_maximisation.py` |
| `count_agreement_patterns_sql()` | function | internal | Produce SQL counting unique comparison-vector patterns in the blocked dataset | `expectation_maximisation.py` |
| `compute_new_parameters_sql()` | function | internal | SQL to compute m/u counts from prediction results | `expectation_maximisation.py` |
| `compute_proportions_for_new_parameters()` | function | internal | Calculate m/u probabilities from counts (DuckDB or pandas path) | `expectation_maximisation.py` |
| `populate_m_u_from_lookup()` | function | internal | Write trained m/u values back to comparison-level objects | `expectation_maximisation.py` |

### 7.2 U Estimation

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `estimate_u_values()` | function | internal | Estimate u probabilities via random sampling of record pairs | `estimate_u.py` |

### 7.3 M Estimation from Labels

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `estimate_m_values_from_label_column()` | function | internal | Train m probabilities from a ground-truth identifier column | `m_training.py` |
| `estimate_m_from_pairwise_labels()` | function | internal | Train m probabilities from a labelled-pairs table | `m_from_labels.py` |

### 7.4 Parameter Records

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `m_u_records_to_lookup_dict()` | function | internal | Convert m/u result records into a lookup dictionary for fast access | `m_u_records_to_parameters.py` |
| `append_m_probability_to_comparison_level_trained_probabilities()` | function | internal | Attach a trained m probability to a comparison level's parameter history | `m_u_records_to_parameters.py` |
| `append_u_probability_to_comparison_level_trained_probabilities()` | function | internal | Same for u probabilities | `m_u_records_to_parameters.py` |

### 7.5 Term Frequencies

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `term_frequencies_for_single_column_sql()` | function | internal | SQL to compute term-frequency proportions for one column | `term_frequencies.py` |
| `compute_all_term_frequencies_sqls()` | function | internal | Full SQL pipeline computing term-frequency tables for every TF-adjusted column | `term_frequencies.py` |
| `colname_to_tf_tablename()` | function | internal | Derive the canonical table name for a column's term-frequency lookup | `term_frequencies.py` |
| `tf_adjustment_chart()` | function | public | Interactive chart showing how TF adjustments shift match weights | `term_frequencies.py` |

---

## 8 Prediction and Scoring

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `predict_from_comparison_vectors_sqls()` | function | internal | Produce the SQL pipeline that converts comparison vectors into match weights and probabilities | `predict.py` |
| `predict_from_comparison_vectors_sqls_using_settings()` | function | internal | Same, but driven from a `Settings` object | `predict.py` |
| `predict_from_agreement_pattern_counts_sqls()` | function | internal | Prediction SQL working from agreement-pattern counts rather than raw vectors | `predict.py` |
| `add_unique_id_and_source_dataset_cols_if_needed()` | function | internal | Augment new records with required ID and source-dataset columns | `find_matches_to_new_records.py` |
| `compare_records()` | function | public | Score two records without instantiating a full Linker (lightweight real-time matching) | `realtime.py` |
| `SQLCache` | class | internal | Cache SQL statements with UID substitution for repeated real-time comparisons | `realtime.py` |

### 8.1 Comparison Vector Computation

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `compute_comparison_vector_values_sql()` | function | internal | SQL to extract gamma columns from blocked pairs | `comparison_vector_values.py` |
| `compute_comparison_vector_values_from_id_pairs_sqls()` | function | internal | SQL pipeline to join ID pairs with input data and compute comparison vectors | `comparison_vector_values.py` |
| `comparison_vector_distribution_sql()` | function | internal | SQL to compute the distribution of comparison vectors in prediction results | `comparison_vector_distribution.py` |

---

## 9 Clustering and Graph Analysis

### 9.1 Connected Components

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `cluster_pairwise_predictions_at_threshold()` | function | public | Cluster predictions into entity groups using connected components at a given threshold | `clustering.py` |
| `cluster_pairwise_predictions_at_multiple_thresholds()` | function | public | Run connected-components clustering at several thresholds for comparison | `clustering.py` |
| `solve_connected_components()` | function | internal | Core connected-components algorithm: iterative SQL-based label propagation | `connected_components.py` |

### 9.2 One-to-One Clustering

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `one_to_one_clustering()` | function | internal | Enforce at most one record per source dataset per cluster | `one_to_one_clustering.py` |
| `drop_ties_sqls()` | function | internal | SQL to break tied match weights during single-best-link clustering | `one_to_one_clustering.py` |

### 9.3 Graph Metrics

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `GraphMetricsResults` | dataclass | public | Container holding `.nodes`, `.edges`, and `.clusters` metric tables | `graph_metrics.py` |
| `compute_edge_metrics()` | function | internal | Compute edge-level metrics including bridge detection via igraph | `edge_metrics.py` |

---

## 10 Evaluation and Accuracy

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `truth_space_table_from_labels_table()` | function | internal | Build a TP/FP/TN/FN truth-space table from labelled pairs | `accuracy.py` |
| `truth_space_table_from_labels_column()` | function | internal | Same, driven by a label column | `accuracy.py` |
| `prediction_errors_from_labels_table()` | function | internal | Extract false positives and false negatives by comparing predictions against labelled pairs | `accuracy.py` |
| `prediction_errors_from_label_column()` | function | internal | Same, driven by a label column | `accuracy.py` |
| `unlinkables_data()` | function | internal | Calculate the proportion of unlinkable records at each threshold | `unlinkables.py` |

---

## 11 Visualization and Charts

### 11.1 Chart Rendering Core

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `load_chart_definition()` | function | internal | Load a Vega-Lite chart spec from a bundled JSON file | `charts.py` |
| `altair_or_json()` | function | internal | Return a chart as an Altair `Chart` object or a plain dict | `charts.py` |
| `save_offline_chart()` | function | public | Write a standalone HTML file embedding a chart and its data | `charts.py` |

### 11.2 Chart Functions

All in `charts.py` unless noted. Visibility is **internal** (called by
Linker sub-APIs which are the public surface).

| Name | Description |
|------|-------------|
| `match_weights_chart()` | Bar chart of comparison-level match weights |
| `m_u_parameters_chart()` | Chart of m and u parameters |
| `match_weights_histogram()` | Histogram of match-weight distribution |
| `waterfall_chart()` | Decomposition of a pairwise comparison's weight |
| `roc_chart()` | ROC curve from truth-space data |
| `precision_recall_chart()` | Precision-recall curve |
| `accuracy_chart()` | Accuracy metrics across thresholds |
| `threshold_selection_tool()` | Interactive threshold picker |
| `parameter_estimate_comparisons()` | Compare parameter estimates across training runs |
| `unlinkables_chart()` | Proportion of unlinkable records |
| `completeness_chart()` | Column completeness across tables |
| `missingness_chart()` | Data completeness / missingness |
| `cumulative_blocking_rule_comparisons_generated()` | Cumulative comparison counts chart |
| `probability_two_random_records_match_iteration_chart()` | Lambda evolution during EM |
| `match_weights_interactive_history_chart()` | Interactive match-weight history with iteration slider |
| `m_u_parameters_interactive_history_chart()` | Interactive m/u history with iteration slider |

### 11.3 Histogram and Waterfall Helpers

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `histogram_data()` | function | internal | Compute histogram bin data from match weights | `match_weights_histogram.py` |
| `records_to_waterfall_data()` | function | internal | Transform pairwise-comparison records into waterfall-chart format | `waterfall_chart.py` |

### 11.4 Interactive Dashboards

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `render_splink_comparison_viewer_html()` | function | internal | Render the comparison-viewer dashboard as a standalone HTML page | `splink_comparison_viewer.py` |
| `comparison_viewer_table_sqls()` | function | internal | SQL pipeline producing the data behind the comparison viewer | `splink_comparison_viewer.py` |
| `render_splink_cluster_studio_html()` | function | internal | Render the cluster-studio dashboard as standalone HTML | `cluster_studio.py` |
| `render_labelling_tool_html()` | function | internal | Render the labelling-tool dashboard as standalone HTML | `labelling_tool.py` |
| `generate_labelling_tool_comparisons()` | function | internal | Produce candidate-match pairs for the labelling tool | `labelling_tool.py` |

### 11.5 Similarity Analysis (pre-linkage exploration)

All in `similarity_analysis.py`; all **public**.

| Name | Kind | Description |
|------|------|-------------|
| `comparator_score()` | function | Calculate similarity scores between two strings using multiple distance metrics |
| `comparator_score_df()` | function | Same, for a list of string pairs; returns a data frame |
| `comparator_score_chart()` | function | Heatmap of string-similarity scores |
| `comparator_score_threshold_chart()` | function | Heatmap filtered by similarity/distance thresholds |
| `phonetic_transform()` | function | Apply Soundex, Metaphone, and Double Metaphone to a string |
| `phonetic_transform_df()` | function | Phonetic transforms for a list of strings |
| `phonetic_match_chart()` | function | Chart of phonetic-match results |

---

## 12 Data Profiling and Exploration

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `profile_columns()` | function | public | Generate profiling charts showing value distributions, top-N, and bottom-N for selected columns | `profile_data.py` |
| `completeness_data()` | function | internal | Calculate the proportion of non-null values per column per table | `completeness.py` |
| `completeness_chart()` | function | public | Chart of column completeness across one or more tables | `completeness.py` |

---

## 13 Database Backends

### 13.1 Abstract Layer

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `DatabaseAPI` | ABC | internal | Abstract base for all backend implementations; defines SQL execution, table registration, caching, and cleanup | `database_api.py` |
| `SplinkDataFrame` | ABC | internal | Abstract wrapper around a backend-specific table; provides `.as_pandas_dataframe()`, `.as_record_dict()`, column listing, and table-drop logic | `splink_dataframe.py` |
| `CacheDictWithLogging` | class | internal | Dictionary-based cache for intermediate query results with an audit trail of executed and cached queries | `cache_dict_with_logging.py` |

Key abstract methods on `DatabaseAPI`:

| Method | Description |
|--------|-------------|
| `_execute_sql_against_backend()` | Run SQL and return a backend-native table object |
| `_table_registration()` | Register external data as a named table |
| `table_to_splink_dataframe()` | Wrap a backend table as a `SplinkDataFrame` |
| `table_exists_in_database()` | Check whether a table exists |

Key template methods on `DatabaseAPI`:

| Method | Description |
|--------|-------------|
| `sql_to_splink_dataframe_checking_cache()` | Execute SQL (or return cached result) and wrap as `SplinkDataFrame` |
| `sql_pipeline_to_splink_dataframe()` | Execute a `CTEPipeline` end-to-end |
| `register_multiple_tables()` | Register several input tables at once |
| `delete_tables_created_by_splink_from_db()` | Clean up all temporary tables |

### 13.2 Concrete Backends

Each backend provides a `DatabaseAPI` subclass and a `SplinkDataFrame`
subclass. The table below notes what is distinctive about each.

| Backend | API Class | DataFrame Class | Notable Features | Directory |
|---------|-----------|-----------------|------------------|-----------|
| DuckDB | `DuckDBAPI` | `DuckDBDataFrame` | In-memory default; `.as_duckdbpyrelation()`; `.to_parquet()` | `duckdb/` |
| SQLite | `SQLiteAPI` | `SQLiteDataFrame` | Registers math and fuzzy-matching UDFs at connect time | `sqlite/` |
| PostgreSQL | `PostgresAPI` | `PostgresDataFrame` | SQLAlchemy engine; auto-creates `splink` schema; registers UDFs and extensions | `postgres/` |
| Spark | `SparkAPI` | `SparkDataFrame` | Lineage-breaking strategies; repartitioning; Scala UDF JAR loading; `.as_spark_dataframe()`, `.to_parquet()`, `.to_csv()` | `spark/` |
| Athena | `AthenaAPI` | `AthenaDataFrame` | S3-backed storage; AWS Wrangler integration; `delete_s3_data` support | `athena/` |

---

## 14 Data Concatenation and Table Plumbing

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `vertically_concatenate_sql()` | function | internal | SQL to UNION multiple input tables, adding a source-dataset column where needed | `vertically_concatenate.py` |
| `enqueue_df_concat_with_tf()` | function | internal | Add concatenated-data-plus-TF SQL to a pipeline with caching | `vertically_concatenate.py` |
| `compute_df_concat_with_tf()` | function | internal | Execute the concatenation-plus-TF pipeline and return the result | `vertically_concatenate.py` |
| `split_df_concat_with_tf_into_two_tables_sqls()` | function | internal | Split a concatenated table by source dataset for two-table linking | `vertically_concatenate.py` |

---

## 15 Datasets

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `SplinkDataSets` | class | public | Lazy-loading container whose properties return demo datasets as data frames | `datasets/splink_datasets.py` |
| `SplinkDataSetLabels` | class | public | Same pattern for ground-truth label tables | `datasets/splink_datasets.py` |

Available datasets: `fake_1000` (250 simulated people with duplicates),
`historical_50k` (Wikidata historical persons), `febrl3`, `febrl4`,
`febrl_synthetic`.

---

## 16 Testing Utilities

| Name | Kind | Visibility | Description | File |
|------|------|------------|-------------|------|
| `is_in_level()` | function | public | Test whether literal values satisfy a comparison level's SQL condition | `testing.py` |
| `comparison_vector_value()` | function | public | Compute the comparison-vector value for literal record(s) against a comparison | `testing.py` |

---

## 17 Utilities and Exceptions

### 17.1 Math Helpers

All in `misc.py`; all **internal**.

| Name | Description |
|------|-------------|
| `prob_to_bayes_factor()` | Convert a probability to a Bayes factor |
| `prob_to_match_weight()` | Convert a probability to a log₂ Bayes factor (match weight) |
| `match_weight_to_bayes_factor()` | Reverse: match weight → Bayes factor |
| `bayes_factor_to_prob()` | Reverse: Bayes factor → probability |
| `interpolate()` | Linear interpolation between two values |
| `calculate_cartesian()` | Cartesian-product size given row counts and link type |

### 17.2 Threshold Normalization

All in `misc.py`; all **internal**.

| Name | Description |
|------|-------------|
| `threshold_args_to_match_weight()` | Normalize probability or weight threshold to a match weight |
| `threshold_args_to_match_prob()` | Normalize to a match probability |
| `threshold_args_to_match_prob_list()` | Normalize a list of thresholds |

### 17.3 General Utilities

All in `misc.py`; all **internal**.

| Name | Description |
|------|-------------|
| `dedupe_preserving_order()` | Remove duplicates from a list while preserving insertion order |
| `ensure_is_list()` | Wrap a scalar in a list; pass lists through unchanged |
| `ascii_uid()` | Generate a random lowercase ASCII identifier |
| `EverythingEncoder` | JSON encoder that handles numpy types and custom objects |
| `read_resource()` | Load a bundled resource file from the package |

### 17.4 Custom Exceptions

All in `exceptions.py`; all **internal**.

| Name | Description |
|------|-------------|
| `SplinkException` | Base exception for all Splink errors |
| `EMTrainingException` | EM-algorithm convergence or configuration errors |
| `ComparisonSettingsException` | Invalid comparison or level configuration |
| `InvalidDialect` | SQL dialect mismatch between settings and backend |
| `MissingDependencyException` | A required package is not installed |
| `InvalidAWSBucketOrDatabase` | AWS Athena resource validation failure |
| `SplinkDeprecated` | Deprecation warning |
| `ErrorLogger` | Collects multiple errors and raises them together with formatted messages |

---

## Summary Counts

| Category | Public | Internal | Total |
|----------|--------|----------|-------|
| Linker sub-API methods | 32 | 4 | 36 |
| Blocking rules & analysis | 10 | 7 | 17 |
| Comparison levels | 21 | 0 | 21 |
| Comparison level composition | 3 | 0 | 3 |
| Comparison library | 19 | 0 | 19 |
| Comparison core classes | 2 | 2 | 4 |
| SQL generation & pipeline | 1 | 14 | 15 |
| Training & EM | 1 | 16 | 17 |
| Prediction & scoring | 1 | 7 | 8 |
| Clustering & graph | 3 | 4 | 7 |
| Evaluation & accuracy | 0 | 5 | 5 |
| Visualization & charts | 8 | 20 | 28 |
| Data profiling | 2 | 1 | 3 |
| Settings & validation | 1 | 15 | 16 |
| Database backends | 0 | 12 | 12 |
| Datasets | 2 | 0 | 2 |
| Testing utilities | 2 | 0 | 2 |
| Math / general utilities | 0 | 18 | 18 |
| **Total** | **~108** | **~125** | **~233** |

> File paths above are relative to `splink/internals/` unless otherwise
> noted. Top-level wrapper modules (e.g. `splink/comparison_library.py`)
> re-export from `splink/internals/` and are not listed separately.
