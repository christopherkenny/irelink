# Package index

## Linkage Specification

Define the comparisons and blocking rules that drive the model.

- [`il_spec()`](http://christophertkenny.com/irelink/reference/il_spec.md)
  : Create an Empty Linkage Specification
- [`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
  : Add a Comparison Layer to a Specification
- [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
  : Add a Prediction Blocking Rule
- [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md)
  : Create a Training-Time Blocking Rule
- [`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md)
  : Compose Multiple Transforms into a Chain
- [`il_substr()`](http://christophertkenny.com/irelink/reference/il_substr.md)
  : Extract a Substring Column Transform
- [`il_regex_extract()`](http://christophertkenny.com/irelink/reference/il_regex_extract.md)
  : Regex Extraction Column Transform
- [`il_nullif()`](http://christophertkenny.com/irelink/reference/il_nullif.md)
  : Replace a Value with NA Column Transform
- [`il_cast_to_string()`](http://christophertkenny.com/irelink/reference/il_cast_to_string.md)
  : Cast to String Column Transform
- [`il_try_parse_date()`](http://christophertkenny.com/irelink/reference/il_try_parse_date.md)
  : Try-Parse Date Column Transform
- [`il_try_parse_timestamp()`](http://christophertkenny.com/irelink/reference/il_try_parse_timestamp.md)
  : Try-Parse Timestamp Column Transform
- [`il_array_element()`](http://christophertkenny.com/irelink/reference/il_array_element.md)
  : Array Element Column Transform
- [`is_il_spec()`](http://christophertkenny.com/irelink/reference/is_il_spec.md)
  : Test if an Object is an irelink Specification

## Comparison Levels

Building blocks for scoring how similar two records are on a given
field.

- [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md)
  : Exact Equality Comparison
- [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md)
  : Levenshtein Edit-Distance Comparison
- [`cl_damerau_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_damerau_levenshtein.md)
  : Damerau-Levenshtein Edit-Distance Comparison
- [`cl_jaro()`](http://christophertkenny.com/irelink/reference/cl_jaro.md)
  : Jaro String Similarity Comparison
- [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md)
  : Jaro-Winkler String Similarity Comparison
- [`cl_jaccard()`](http://christophertkenny.com/irelink/reference/cl_jaccard.md)
  : Jaccard Set Similarity Comparison
- [`cl_cosine()`](http://christophertkenny.com/irelink/reference/cl_cosine.md)
  : Cosine Similarity Comparison
- [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md)
  : Numeric Absolute Difference Comparison
- [`cl_pct_diff()`](http://christophertkenny.com/irelink/reference/cl_pct_diff.md)
  : Numeric Percentage Difference Comparison
- [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
  : Date Difference Comparison
- [`cl_time_diff()`](http://christophertkenny.com/irelink/reference/cl_time_diff.md)
  : Time Difference Comparison
- [`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md)
  : Geographic Distance Comparison
- [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md)
  : Array Intersection Comparison
- [`cl_array_subset()`](http://christophertkenny.com/irelink/reference/cl_array_subset.md)
  : Array Subset Comparison
- [`cl_array_min_distance()`](http://christophertkenny.com/irelink/reference/cl_array_min_distance.md)
  : Pairwise Array Minimum Distance Comparison
- [`cl_columns_reversed()`](http://christophertkenny.com/irelink/reference/cl_columns_reversed.md)
  : Swap Detection for Two Columns
- [`cl_custom()`](http://christophertkenny.com/irelink/reference/cl_custom.md)
  : Custom SQL Comparison
- [`cl_literal()`](http://christophertkenny.com/irelink/reference/cl_literal.md)
  : Literal Value Comparison
- [`cl_null()`](http://christophertkenny.com/irelink/reference/cl_null.md)
  : Null / Missing Value Level
- [`cl_else()`](http://christophertkenny.com/irelink/reference/cl_else.md)
  : Catch-All Else Level
- [`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md)
  : Compose Custom Comparison Levels
- [`cl_and()`](http://christophertkenny.com/irelink/reference/cl_and.md)
  : Combine Comparison Conditions with AND
- [`cl_or()`](http://christophertkenny.com/irelink/reference/cl_or.md) :
  Combine Comparison Conditions with OR
- [`cl_not()`](http://christophertkenny.com/irelink/reference/cl_not.md)
  : Negate a Comparison Condition

## Phonetic Transforms

Phonetic encoding functions for blocking and comparison on name fields.

- [`il_soundex()`](http://christophertkenny.com/irelink/reference/phonetic.md)
  [`il_metaphone()`](http://christophertkenny.com/irelink/reference/phonetic.md)
  [`il_dmetaphone()`](http://christophertkenny.com/irelink/reference/phonetic.md)
  : Phonetic Transform Functions
- [`cl_soundex()`](http://christophertkenny.com/irelink/reference/cl_soundex.md)
  : Soundex Phonetic Comparison

## Domain-Specific Comparisons

Pre-configured multi-level comparisons for common field types.

- [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md)
  : Personal Name Comparison
- [`cl_first_last_name()`](http://christophertkenny.com/irelink/reference/cl_first_last_name.md)
  : First Name and Last Name Comparison with Swap Detection
- [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md)
  : Forename and Surname Comparison with Swap Detection
- [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md)
  : Date of Birth Comparison
- [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md)
  : Email Address Comparison
- [`cl_zip_code()`](http://christophertkenny.com/irelink/reference/cl_zip_code.md)
  : ZIP Code Comparison
- [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md)
  : Postcode Comparison

## Model Fitting

Create and train a probabilistic linkage model.

- [`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
  : Create a Linkage Model
- [`il_estimate_u()`](http://christophertkenny.com/irelink/reference/il_estimate_u.md)
  : Estimate Non-Match (u) Parameters
- [`il_estimate_em()`](http://christophertkenny.com/irelink/reference/il_estimate_em.md)
  : Train Parameters via Expectation-Maximization
- [`il_estimate_prior()`](http://christophertkenny.com/irelink/reference/il_estimate_prior.md)
  : Estimate the Prior Match Probability
- [`il_prior_prevalence()`](http://christophertkenny.com/irelink/reference/il_prior_prevalence.md)
  : Add a Prevalence Prior
- [`il_prior_m()`](http://christophertkenny.com/irelink/reference/il_prior_m.md)
  : Add a Matched-Class Comparison Prior
- [`il_constrain_m()`](http://christophertkenny.com/irelink/reference/il_constrain_m.md)
  : Add a Fixed Matched-Class Constraint
- [`il_estimate_m_from_column()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_column.md)
  : Estimate Match (m) Parameters from a Label Column
- [`il_estimate_m_from_labels()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_labels.md)
  : Estimate Match (m) Parameters from Labeled Data
- [`is_il_model()`](http://christophertkenny.com/irelink/reference/is_il_model.md)
  : Test if an Object is an irelink Model

## Prediction and Clustering

Score record pairs and resolve them into linked entities.

- [`predict(`*`<il_model>`*`)`](http://christophertkenny.com/irelink/reference/predict.il_model.md)
  : Score Record Pairs from a Trained Model
- [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
  : Cluster Scored Pairs into Entities
- [`il_deterministic_link()`](http://christophertkenny.com/irelink/reference/il_deterministic_link.md)
  : Deterministic Record Linkage
- [`il_find_matches()`](http://christophertkenny.com/irelink/reference/il_find_matches.md)
  : Find Matches for New Records
- [`il_score_patterns()`](http://christophertkenny.com/irelink/reference/il_score_patterns.md)
  : Score Comparison Patterns
- [`il_score_missing_edges()`](http://christophertkenny.com/irelink/reference/il_score_missing_edges.md)
  : Score Missing Edges Within Clusters

## Model Inspection

Examine parameters, weights, and training diagnostics.

- [`il_parameters()`](http://christophertkenny.com/irelink/reference/il_parameters.md)
  : Extract Model Parameters
- [`il_priors()`](http://christophertkenny.com/irelink/reference/il_priors.md)
  : Inspect Model Priors
- [`il_constraints()`](http://christophertkenny.com/irelink/reference/il_constraints.md)
  : Inspect Model Constraints
- [`il_weights()`](http://christophertkenny.com/irelink/reference/il_weights.md)
  : Extract Match Weights by Comparison Level
- [`il_training_history()`](http://christophertkenny.com/irelink/reference/il_training_history.md)
  : Extract EM Training History
- [`autoplot(`*`<il_training_history>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_training_history.md)
  : Plot EM Training History
- [`il_waterfall()`](http://christophertkenny.com/irelink/reference/il_waterfall.md)
  : Extract Waterfall Data for a Single Pair
- [`il_compare_records()`](http://christophertkenny.com/irelink/reference/il_compare_records.md)
  : Compare Two Individual Records
- [`il_string_similarity()`](http://christophertkenny.com/irelink/reference/il_string_similarity.md)
  : Compute String Similarity Scores
- [`autoplot(`*`<il_string_similarity>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_string_similarity.md)
  : Comparator Score Bar Chart
- [`il_tf_chart()`](http://christophertkenny.com/irelink/reference/il_tf_chart.md)
  : Term Frequency Adjustment Chart
- [`il_comparison_vectors()`](http://christophertkenny.com/irelink/reference/il_comparison_vectors.md)
  : Comparison Vector Distribution
- [`autoplot(`*`<il_comparison_vectors>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_comparison_vectors.md)
  : Plot comparison vector distribution
- [`print(`*`<il_model>`*`)`](http://christophertkenny.com/irelink/reference/print.il_model.md)
  : Print an irelink Model
- [`print(`*`<il_spec>`*`)`](http://christophertkenny.com/irelink/reference/print.il_spec.md)
  : Print an irelink Specification
- [`summary(`*`<il_model>`*`)`](http://christophertkenny.com/irelink/reference/summary.il_model.md)
  : Summarize an irelink Model
- [`autoplot(`*`<il_model>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_model.md)
  : Quick Match-Weights Plot for a Model
- [`autoplot(`*`<il_compared>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_compared.md)
  : Quick Plot for Scored Pairs

## Evaluation

Assess model quality against labeled data.

- [`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md)
  : Accuracy Metrics Across Thresholds
- [`il_confusion_matrix()`](http://christophertkenny.com/irelink/reference/il_confusion_matrix.md)
  : Confusion Matrix at a Threshold
- [`il_cluster_confusion_matrix()`](http://christophertkenny.com/irelink/reference/il_cluster_confusion_matrix.md)
  : Cluster-Level Confusion Matrix for Deduplication
- [`labels_from_column()`](http://christophertkenny.com/irelink/reference/labels_from_column.md)
  : Derive Pairwise Labels from a Ground-Truth Column
- [`il_precision_recall()`](http://christophertkenny.com/irelink/reference/il_precision_recall.md)
  : Compute Precision-Recall Curve Data
- [`il_roc()`](http://christophertkenny.com/irelink/reference/il_roc.md)
  : Compute ROC Curve Data
- [`il_errors()`](http://christophertkenny.com/irelink/reference/il_errors.md)
  : Identify Prediction Errors
- [`il_unlinkables()`](http://christophertkenny.com/irelink/reference/il_unlinkables.md)
  : Compute Unlinkable Records
- [`il_graph_metrics()`](http://christophertkenny.com/irelink/reference/il_graph_metrics.md)
  : Compute Graph Metrics for Clusters
- [`autoplot(`*`<il_accuracy>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_accuracy.md)
  : Plot Accuracy Metrics Across Thresholds
- [`autoplot(`*`<il_roc>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_roc.md)
  : Plot ROC Curve
- [`autoplot(`*`<il_precision_recall>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_precision_recall.md)
  : Plot Precision–Recall Curve
- [`autoplot(`*`<il_unlinkables>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_unlinkables.md)
  : Plot Unlinkables Curve

## Blocking

Suggest and evaluate blocking rules to reduce candidate pairs.

- [`il_suggest_blocking()`](http://christophertkenny.com/irelink/reference/il_suggest_blocking.md)
  : Suggest Blocking Rules
- [`il_find_blocking_below()`](http://christophertkenny.com/irelink/reference/il_find_blocking_below.md)
  : Find Blocking Rules Below a Pair-Count Threshold
- [`block_from_labels()`](http://christophertkenny.com/irelink/reference/block_from_labels.md)
  : Derive Blocking Rules from Labeled Pairs

## Data Profiling

Explore and summarize input data before linkage.

- [`il_completeness()`](http://christophertkenny.com/irelink/reference/il_completeness.md)
  : Column Completeness Across Datasets
- [`autoplot(`*`<il_completeness>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_completeness.md)
  : Plot Column Completeness
- [`il_count_pairs()`](http://christophertkenny.com/irelink/reference/il_count_pairs.md)
  : Count Candidate Pairs Under Blocking Rules
- [`autoplot(`*`<il_count_pairs>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_count_pairs.md)
  : Plot Blocking Rule Pair Counts
- [`il_largest_blocks()`](http://christophertkenny.com/irelink/reference/il_largest_blocks.md)
  : Identify the Largest Blocking Bins
- [`il_profile()`](http://christophertkenny.com/irelink/reference/il_profile.md)
  : Profile Column Value Distributions
- [`autoplot(`*`<il_profile>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_profile.md)
  : Plot Column Value Profiles
- [`il_comparator_score()`](http://christophertkenny.com/irelink/reference/il_comparator_score.md)
  : Batch String Similarity Scores
- [`autoplot(`*`<il_comparator_score>`*`)`](http://christophertkenny.com/irelink/reference/autoplot.il_comparator_score.md)
  : Plot batch comparator scores
- [`il_comparator_threshold_chart()`](http://christophertkenny.com/irelink/reference/il_comparator_threshold_chart.md)
  : Comparator Score Threshold Chart
- [`il_phonetic_chart()`](http://christophertkenny.com/irelink/reference/il_phonetic_chart.md)
  : Phonetic Match Chart
- [`il_register_tf()`](http://christophertkenny.com/irelink/reference/il_register_tf.md)
  : Register Pre-Computed Term Frequency Tables

## Persistence and Utilities

Save, load, and manage linkage models and resources.

- [`il_save()`](http://christophertkenny.com/irelink/reference/il_save.md)
  : Save a Model to Disk
- [`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md)
  : Load a Saved Model
- [`il_attach()`](http://christophertkenny.com/irelink/reference/il_attach.md)
  : Attach a Saved Model to Fresh Data
- [`il_cleanup()`](http://christophertkenny.com/irelink/reference/il_cleanup.md)
  : Remove Model-Owned Temporary Tables from Database
- [`il_cleanup_all()`](http://christophertkenny.com/irelink/reference/il_cleanup_all.md)
  : Remove All irelink Temporary Tables from a Database
- [`irelink`](http://christophertkenny.com/irelink/reference/irelink-package.md)
  [`irelink-package`](http://christophertkenny.com/irelink/reference/irelink-package.md)
  : irelink: Fast Probabilistic Record Linkage

## Datasets

Bundled benchmark datasets from the splink ecosystem.

- [`fake_20`](http://christophertkenny.com/irelink/reference/fake_20.md)
  : Fake 20 — Minimal Deduplication Example
- [`fake_1000`](http://christophertkenny.com/irelink/reference/fake_1000.md)
  : Splink Fake 1000 — Deduplication Benchmark
- [`fake_1000_labels`](http://christophertkenny.com/irelink/reference/fake_1000_labels.md)
  : Splink Fake 1000 — Clerical Pairwise Labels
- [`febrl4a`](http://christophertkenny.com/irelink/reference/febrl4a.md)
  : FEBRL 4a — Record Linkage Original Records
- [`febrl4b`](http://christophertkenny.com/irelink/reference/febrl4b.md)
  : FEBRL 4b — Record Linkage Duplicate Records

## Unit Helpers

Lightweight constructors for physical and temporal units.

- [`days()`](http://christophertkenny.com/irelink/reference/days.md) :
  Create a Duration in Days
- [`months()`](http://christophertkenny.com/irelink/reference/months.md)
  : Create a Duration in Months
- [`years()`](http://christophertkenny.com/irelink/reference/years.md) :
  Create a Duration in Years
- [`hours()`](http://christophertkenny.com/irelink/reference/hours.md) :
  Create a Duration in Hours
- [`minutes()`](http://christophertkenny.com/irelink/reference/minutes.md)
  : Create a Duration in Minutes
- [`seconds()`](http://christophertkenny.com/irelink/reference/seconds.md)
  : Create a Duration in Seconds
- [`km()`](http://christophertkenny.com/irelink/reference/km.md) :
  Create a Distance in Kilometres
- [`mi()`](http://christophertkenny.com/irelink/reference/mi.md) :
  Create a Distance in Miles
