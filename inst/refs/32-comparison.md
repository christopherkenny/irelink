# irelink vs splink: Deep Comparison
\
> Compares irelink (R) against
> [splink](https://github.com/moj-analytical-services/splink) (Python v4).
> All claims verified by reading actual source code in both repositories.

---

## 1. Architecture Overview

| Aspect | irelink | splink |
|--------|---------|--------|
| Language | R | Python |
| Primary backend | DuckDB (+ PostgreSQL, SQLite) | DuckDB, Spark, PostgreSQL, SQLite, Athena |
| API style | Pipe-based spec builder | Component-based Linker |
| SQL strategy | `glue::glue()` string interpolation | CTE pipeline with sqlglot dialect translation |
| Model object | S3 `il_model` with `$spec`, `$params`, `$con`, `$data` | `Linker` class with component classes |
| Dialect handling | `detect_dialect()` + `dialect_has_fuzzy_sql()` | `SplinkDialect` abstract factory |
| SQL parsing | None (manual string building) | sqlglot for column extraction, dialect translation |

### Key Structural Differences

**CTE Pipeline:** splink uses a `CTEPipeline` (`pipeline.py`) that chains SQL
operations as Common Table Expressions with hash-based caching and table
reference resolution. irelink builds SQL directly via `glue::glue()` in
`R/utils-sql.R`, executing immediately through DBI as nested subqueries.

**SQL Dialect Translation:** splink uses sqlglot (`sql_transform.py`,
`parse_sql.py`) for cross-dialect SQL translation and column extraction. This
allows blocking rules and custom SQL to be written in one dialect and
automatically translated to another. irelink has no equivalent — SQL is
generated for the detected dialect directly, and custom SQL (`.where` in
`il_block_on()`, `cl_custom()`) must be written in the target dialect.

---

## 2. Comparison Functions

### 2a. Coverage Matrix

| splink Comparison | irelink Equivalent | Notes |
|---|---|---|
| `ExactMatch` | `cl_exact()` | |
| `LevenshteinAtThresholds` | `cl_levenshtein()` | |
| `DamerauLevenshteinAtThresholds` | `cl_damerau_levenshtein()` | |
| `JaroAtThresholds` | `cl_jaro()` | |
| `JaroWinklerAtThresholds` | `cl_jaro_winkler()` | |
| `JaccardAtThresholds` | `cl_jaccard()` | |
| `CosineSimilarityAtThresholds` | `cl_cosine()` | |
| `AbsoluteDateDifferenceAtThresholds` | `cl_date_diff()` | Unit-tagged: `days()`, `months()`, `years()` |
| `AbsoluteTimeDifferenceAtThresholds` | `cl_time_diff()` | Unit-tagged: `seconds()`, `minutes()`, `hours()` |
| `DistanceInKMAtThresholds` | `cl_distance_km()` | Also supports `mi()` for miles |
| `ArrayIntersectAtSizes` | `cl_array_intersect()` | |
| `DateOfBirthComparison` | `cl_dob()` | |
| `EmailComparison` | `cl_email()` | |
| `NameComparison` | `cl_name()` | Adds optional `phonetic` arg |
| `ForenameSurnameComparison` | `cl_forename_surname()` | Also aliased `cl_first_last_name()` |
| `PostcodeComparison` | `cl_postcode()` | UK postcode hierarchy + optional geo fallback |
| `CustomComparison` | `cl_custom()` / `cl_levels()` | |
| `DistanceFunctionAtThresholds` | `cl_custom()` | No generic wrapper; use `cl_custom()` with raw SQL |
| `PairwiseStringDistanceFunctionAtThresholds` | `cl_array_min_distance()` | Uses UNNEST cross-join |

### 2b. Comparison Levels Coverage

| splink Level | irelink Equivalent |
|---|---|
| `NullLevel` | `cl_null()` |
| `ElseLevel` | `cl_else()` |
| `ExactMatchLevel` | `cl_exact()` |
| `LiteralMatchLevel` | `cl_literal()` |
| `ColumnsReversedLevel` | `cl_columns_reversed()` |
| `LevenshteinLevel` | `cl_levenshtein(N)` |
| `DamerauLevenshteinLevel` | `cl_damerau_levenshtein(N)` |
| `JaroLevel` | `cl_jaro(N)` |
| `JaroWinklerLevel` | `cl_jaro_winkler(N)` |
| `JaccardLevel` | `cl_jaccard(N)` |
| `CosineSimilarityLevel` | `cl_cosine(N)` |
| `AbsoluteDifferenceLevel` | `cl_numeric_diff()` |
| `PercentageDifferenceLevel` | `cl_pct_diff()` |
| `AbsoluteDateDifferenceLevel` | `cl_date_diff()` |
| `AbsoluteTimeDifferenceLevel` | `cl_time_diff()` |
| `DistanceInKMLevel` | `cl_distance_km()` |
| `ArrayIntersectLevel` | `cl_array_intersect()` |
| `ArraySubsetLevel` | `cl_array_subset()` |
| `DistanceFunctionLevel` | `cl_custom()` (indirect) |
| `PairwiseStringDistanceFunctionLevel` | `cl_array_min_distance()` |
| `CustomLevel` | `cl_custom()` |
| `And` | `cl_and()` |
| `Or` | `cl_or()` |
| `Not` | `cl_not()` |

### 2c. Column Expression / Transforms

| splink Transform | irelink Equivalent | Status |
|---|---|---|
| `.lower()` | `tolower` (via `transform` arg) | ✅ Present |
| `.substr(start, len)` | `il_substr(start, len)` | ✅ Present |
| `.regex_extract(pattern, group)` | `il_regex_extract(pattern, group)` | ✅ Present |
| `.nullif(value)` | `il_nullif(value)` | ✅ Present |
| `.cast_to_string()` | `il_cast_to_string()` | ✅ Present (`R/il_column_transforms.R:123`) |
| `.try_parse_date(format)` | `il_try_parse_date(format)` | ✅ Present (`R/il_column_transforms.R:149`) |
| `.try_parse_timestamp(format)` | `il_try_parse_timestamp()` | ✅ FIXED |
| `.access_extreme_array_element(first_or_last)` | `il_array_element(position)` | ✅ Present (`R/il_column_transforms.R:173`) |

### 2d. Features Only in irelink

| Feature | File | Notes |
|---|---|---|
| `cl_soundex()` | `R/cl_domain.R` | Pre-built phonetic comparison level |
| `cl_zip_code()` | `R/cl_domain.R` | US ZIP code with SCF (3-digit) fallback |
| `cl_first_last_name()` | `R/cl_domain.R` | American naming alias for `cl_forename_surname()` |
| `cl_domain()` | `R/cl_domain.R` | Domain extraction comparison |
| Miles support | `R/cl_distance_km.R` | `mi()` unit in addition to `km()` |
| `il_soundex` | `R/il_phonetic.R` | Phonetic transform for blocking and comparison |
| `il_metaphone` | `R/il_phonetic.R` | PostgreSQL only |
| `il_dmetaphone` | `R/il_phonetic.R` | PostgreSQL only |
| `il_transform()` | `R/il_column_transforms.R` | Compose multiple transforms into a chain |

---

## 3. Blocking

### 3a. Feature Comparison

| Feature | irelink | splink | Notes |
|---|---|---|---|
| Column-equality blocking | `il_block_on(col1, col2)` | `block_on("col1", "col2")` | Parity |
| Custom SQL conditions | `.where` parameter | `CustomRule("sql")` | Parity |
| Phonetic blocking | `.transform = il_soundex` | Must embed in SQL | **irelink only** |
| Array explosion | `.explode` parameter | `ExplodingBlockingRule` | Parity |
| OR semantics | Multiple `il_block_on()` calls | Multiple rules in list | Parity |
| AND semantics | Multiple columns in one call | Multiple columns in one rule | Parity |
| Rule negation | — | `Not()` | **splink only** (minor) |
| Pair counting | `il_count_pairs()` | `count_comparisons_from_blocking_rule()` | Parity |
| Largest blocks | `il_largest_blocks()` | `n_largest_blocks()` | Parity |
| Rule suggestion | `il_suggest_blocking()` | `suggest_blocking_rules()` | See §3b |
| Rules below threshold | `il_find_blocking_below()` | `find_brs_below_threshold()` | Parity |
| Block from labels | `block_from_labels()` | — | **irelink only** |
| Cost optimisation | — | `optimise_cost_of_brs.py` | See §3b |
| Cumulative analysis | `il_count_pairs()` + `autoplot()` | `blocking_analysis.py` | Parity (see §3c) |
| Salting | — | `SaltedBlockingRule` | Spark only; see §3d |

### 3b. Blocking Rule Suggestion

Both packages suggest blocking rules, but with different approaches:

**splink** uses a two-stage process:
1. `find_blocking_rules_below_threshold_comparison_count()` — exhaustive tree
   search of all column combinations, pruning branches that exceed the
   threshold. Returns candidate rules with comparison counts and equi-join
   counts. (`find_brs_with_comparison_counts_below_threshold.py:87-280`)
2. `suggest_blocking_rules()` — multi-objective cost optimisation over
   candidates. Runs a heuristic N times (default 100) optimising for field
   freedom, number of rules, and comparison count.
   (`optimise_cost_of_brs.py:123-218`)

**irelink** uses a single function `il_suggest_blocking()` that enumerates
column combinations up to `max_depth` (default 1, optionally 2), computes
coverage and pair counts, and scores by `coverage × (1 - pct_of_cartesian)`.
(`R/il_suggest_blocking.R:41-86`)

The cost-optimised suggestion (stage 2 in splink) has no irelink equivalent.
Users must manually select from `il_suggest_blocking()` results.

**irelink-only:** `block_from_labels()` derives blocking rule effectiveness
from labeled pairs, computing recall per column — which columns catch the
most true matches. (`R/il_suggest_blocking.R:197-247`)

### 3c. ~~Cumulative Blocking Analysis~~ — Already at parity

irelink's `il_count_pairs()` computes `cumulative_pairs` across multiple
blocking rules (via SQL `UNION` to count unique pairs cumulatively,
`R/il_count_pairs.R:149-167`). `autoplot.il_count_pairs(type = 'additional')`
visualises per-rule marginal impact as a horizontal bar chart titled
"Cumulative Pairs by Blocking Rule" (`R/autoplot.R:290-348`). This is
functionally equivalent to splink's
`cumulative_comparisons_to_be_scored_from_blocking_rules_data()`.

### 3d. Salting

splink's `SaltedBlockingRule` (`blocking.py:319-380`) partitions large blocks
into N salt buckets for parallelism. The splink documentation explicitly
states: **"Note that salting is only available for the Spark backend"**
(`docs/topic_guides/performance/salting.md:16`).

Since irelink does not support the Spark backend, salting is not a relevant
gap. The `salting_required` property in `settings.py:644-654` does return
`True` for DuckDB, but this only adds a `random() AS __splink_salt` column
for internal DuckDB parallelisation — it does not expose the user-facing
`SaltedBlockingRule` feature to DuckDB users.

### 3e. ~~Preceding-Rule Deduplication~~ — FIXED

When multiple blocking rules are used, the same pair can be generated by more
than one rule. Both packages now handle this the same way:

Each subsequent blocking rule adds
`AND NOT (coalesce((rule_1), false) OR coalesce((rule_2), false) ...)` to its
WHERE clause. This prevents duplicate pairs from being generated in the first
place.

In splink: `blocking.py:151-184`.
In irelink: `build_gamma_query()` in `R/utils-sql.R`.

---

## 4. EM Estimation

### 4a. Core Algorithm

Both implement the same Fellegi-Sunter EM algorithm: E-step (posterior match
probability per agreement pattern), M-step (update m/u weighted by posterior),
convergence check (max parameter change < threshold).

**Key implementation difference:** Both packages support two EM modes:

- **Per-pair TF mode (splink default `estimate_without_term_frequencies=False`,
  irelink `estimate_without_tf=FALSE`):** EM operates on individual pairs.
  Each pair's E-step match probability includes its per-pair TF adjustment, so
  pairs with the same gamma pattern but different TF values get different
  posterior weights. The M-step sums over individual pairs (each with count 1).
  splink: `expectation_maximisation.py:290-297`.
  irelink: `il_estimate_em.R` lines 145-152, 242-268 (E-step TF adjustment via
  `compute_tf_adjustment()` formula: `log(u_exact / max(tf_l, tf_r))`).

- **Aggregated mode (splink `estimate_without_term_frequencies=True`,
  irelink `estimate_without_tf=TRUE` — **irelink default**):** EM operates on
  aggregated gamma-pattern counts (no TF). Faster (~100-1000 patterns vs
  millions of pairs). `expectation_maximisation.py:269-273`.

**Note on defaults:** splink defaults to per-pair TF mode; irelink defaults to
aggregated mode for performance. Users can switch with `estimate_without_tf`.

| Feature | irelink | splink |
|---|---|---|
| EM computation | R-side (both modes) | SQL-side per iteration |
| TF during EM | `estimate_without_tf=FALSE` | Default: yes; opt-out: `estimate_without_term_frequencies=True` |
| Default TF mode | Aggregated (no TF) | Per-pair TF |
| Convergence threshold | `1e-5` (default) | `1e-4` (default) |
| Max iterations | 25 (default) | 25 (default) |
| Fix u parameters | `fix_u = TRUE` (default) | Via `training_fixed_probabilities` |
| Fix m parameters | `fix_m = FALSE` (default) | Via `training_fixed_probabilities` |
| Fix prior | `fix_prior = TRUE` (default) | Via `training_fixed_probabilities` |
| Laplace smoothing | `+0.5/nl` prevents zero estimates | Not explicit |
| Prior derivation | `derive_prior = TRUE` option | — (**irelink only**) |
| Training history | `model$params$history` | `EMTrainingSession._iteration_history` |
| Column deactivation | Automatic (via `$columns` slot) | Automatic (`em_training_session.py:98-125`) |
| Blocking-adjusted prior | Automatic (pre-EM) | Automatic (`em_training_session.py:289-320`) |

### 4b. ~~EM Column Deactivation~~ — FIXED

When training with a blocking rule like `block_on("surname")`, both packages
now automatically detect that the "surname" comparison overlaps with the
blocking columns. splink uses sqlglot to parse column names from blocking SQL
(`em_training_session.py:98-125`); irelink uses the `$columns` slot on
blocking rule objects (no SQL parsing needed). Deactivated comparisons are
skipped in the M-step — their m/u parameters remain at defaults.

### 4c. ~~Blocking-Adjusted Prior~~ — FIXED

Both packages now adjust the prior `probability_two_random_records_match`
when training under a blocking rule. The prior Bayes factor is multiplied by
the exact-match BFs (`m_top / u_top`) of deactivated comparisons. In irelink
this happens once before the EM loop starts. Formula:
`prior_bf = (prior / (1 - prior)) * prod(m_top / u_top)` then
`adjusted_prior = prior_bf / (1 + prior_bf)`.

### 4d. Prior Derivation (irelink only)

irelink has a `derive_prior = TRUE` option (`il_estimate_em.R:277-281`) that
computes the prior from trained parameters after EM converges:

```r
derive_prior_from_params <- function(m_list, u_list, pattern_mat, pattern_n) {
  # Weighted average posterior match probability with a flat 0.5 prior
  bf <- exp(sum_log_bf_per_pattern)
  sum((bf / (1 + bf)) * pattern_n) / sum(pattern_n)
}
```

splink has no equivalent.

---

## 5. Prediction / Scoring

### 5a. Match Weight Formula

Both use the same Fellegi-Sunter formula and are **mathematically identical**:

- irelink: `match_weight = Σ log2(m_k / u_k)` (sum of log BFs per comparison)
- splink: `bf_combined = prior_bf × Π(m_k / u_k)` then `log2(bf_combined)`

Since `log(A×B) = log(A) + log(B)`, these produce the same result.

Match probability transform:
- irelink: `1 / (1 + exp(-(log_prior_odds + match_weight × ln2)))`
- splink: `bf_combined / (1 + bf_combined)` with infinity check

Both are the same logistic transform.

### 5b. SQL Generation

irelink's scoring SQL (`R/utils-sql.R:933-1014`):
```sql
SELECT DISTINCT unique_id_l, unique_id_r, gamma_*,
  (CASE gamma_col1 WHEN 0 THEN w0 WHEN 1 THEN w1 ... END + ...) AS match_weight,
  1.0 / (1.0 + EXP(-(prior_log_odds + match_weight * ln2))) AS match_probability
FROM gamma_pairs
WHERE match_probability >= threshold
```

splink's scoring SQL (`predict.py:113-128`):
```sql
SELECT log2(bf_combined) AS match_weight,
  CASE WHEN any_bf_infinity THEN 1.0
       ELSE bf_combined / (1 + bf_combined) END AS match_probability
FROM (
  SELECT LEAST(GREATEST(bf_prior * bf_col1 * bf_col2 * ..., 1e-300), 1e300)
    AS bf_combined ...
)
```

Both are **correct and produce equivalent results**.

| Feature | irelink | splink |
|---|---|---|
| Edge case handling | `pmax(m, 1e-10)` floor | `LEAST(GREATEST(bf, 1e-300), 1e300)` + ∞ check |
| Threshold filtering | SQL WHERE clause | SQL WHERE clause |
| Lazy prediction | `collect = FALSE` → `il_compared_lazy` | Returns `SplinkDataFrame` (always lazy) |
| Include original fields | `include_fields = TRUE` via LEFT JOIN | `retain_matching_columns` setting |

---

## 6. Term Frequency

### 6a. TF Adjustment Formula

Both packages use the **same core formula**: `u_exact / max(tf_l, tf_r)`.

- irelink: `log2(u_exact / GREATEST(tf_l, tf_r))` added to match weight sum
  (`R/utils-sql.R:911-921`)
- splink: `POW(u_exact / max(tf_l, tf_r), tf_adjustment_weight)` as a
  multiplicative Bayes factor (`comparison_level.py:610-642`)

splink's divisor is computed as
`CASE WHEN coalesce(tf_l, tf_r) >= coalesce(tf_r, tf_l) THEN coalesce(tf_l, tf_r) ELSE coalesce(tf_r, tf_l)` —
which is equivalent to `GREATEST(tf_l, tf_r)` with NULL-coalesce protection.

| Feature | irelink | splink |
|---|---|---|
| TF formula | `COUNT(value) / COUNT(non-null)` | Same |
| TF table name | `__il_tf_<col>` | `__splink__df_tf_<col>` |
| L/R strategy | `GREATEST(tf_l, tf_r)` | Same (coalesce wrapper) |
| NULL handling | Skip if either side NULL | Coalesce: use whichever exists |
| Applied to | Exact match level only | Per-level, configurable |
| Weight parameter | `tf_adjustment_weight` (default 1.0) | `tf_adjustment_weight` (default 1.0) |
| Minimum u floor | `tf_minimum_u_value` (default 0.0) | `tf_minimum_u_value` (default 0.0) |
| External TF data | `il_register_tf()` | Computed during vertical concatenation |

### 6b. Minor Differences

**`tf_adjustment_weight`:** Both packages now support this parameter (default
1.0). Raises the TF Bayes factor to a configurable power. Setting to 0.5
halves the TF adjustment in log-space. In irelink, set via `il_compare()`.

**`tf_minimum_u_value`:** Both packages now support this parameter (default
0.0). Configurable floor for the TF divisor. In irelink, set via `il_compare()`.

**NULL handling:** splink's coalesce approach gracefully handles cases where
only one side has a TF value. irelink requires both sides to have TF values;
otherwise the adjustment is skipped (returns 0). This is a design choice —
irelink is more conservative about applying TF when data is incomplete.

---

## 7. Clustering

### 7a. Connected Components

Both implement the same iterative representative propagation algorithm:
bidirectional edges → each node is its own representative → iteratively update
representative = MIN(representative) across neighbours → converge when no
updates.

| Feature | irelink | splink |
|---|---|---|
| Algorithm | Representative propagation | Same |
| Implementation | `R/utils-cc.R` | `connected_components.py` |
| Node universe | Inferred from edges | Accepts separate `nodes_table` |
| Max iterations | 100 (safety valve) | No explicit limit |
| igraph fallback | Yes (for SQLite) | For bridge detection only |

### 7b. ~~One-to-One Clustering~~ — FIXED

Both packages support one-to-one (best-link) clustering with the same
iterative algorithm:

**Algorithm** (`one_to_one_clustering.py:103-338` / `utils-cc.R:solve_one_to_one_sql()`):
Iterative algorithm that enforces at most one record from each specified
source dataset per cluster. Each iteration: (1) tracks per-cluster dataset
containment via `GROUP BY representative`, (2) ranks candidate edges by
match probability, excluding edges that would merge two clusters containing
the same source dataset, (3) keeps only mutual best matches (rank 1 on both
sides), (4) updates representatives via `MIN(representative)`. Iterates
until convergence (no more merges possible).

Both SQL and R paths are available: `solve_one_to_one_sql()` for DuckDB/
PostgreSQL, `solve_one_to_one_r()` for igraph fallback. Both support
`"drop"` and `"lowest_id"` tie-handling.

**Implementation:** When `source_dataset` is provided with `method = "best_link"`,
irelink now uses the iterative algorithm (`il_cluster.R` lines 127-152) instead
of the previous single-pass filter. This matches splink's behaviour for
multi-source linking where edges that were not mutual-best initially can
become viable as clusters form.

### 7c. Graph Metrics

Both compute equivalent graph metrics:

| Metric | irelink (`il_graph_metrics.R`) | splink (`graph_metrics.py`) |
|---|---|---|
| Node degree | ✅ | ✅ |
| Node centrality | ✅ | ✅ |
| Cluster size | ✅ | ✅ |
| Cluster density | ✅ | ✅ |
| Cluster centralisation | ✅ | ✅ |
| Bridge detection | ✅ (igraph) | ✅ (igraph) |

irelink also has `il_score_missing_edges()` for scoring within-cluster pairs
missed by blocking — no splink equivalent.

---

## 8. Evaluation

| Feature | irelink | splink | Notes |
|---|---|---|---|
| Confusion matrix (TP/FP/FN/TN) | `il_accuracy()` | `accuracy.py:262-265` | Parity |
| Precision & Recall | `il_accuracy()` | `accuracy.py:272-273` | Parity |
| F1 score | `il_accuracy()` | `accuracy.py:277` | Parity |
| F2, F0.5 scores | `il_accuracy()` | `accuracy.py:278-279` | ✅ FIXED |
| Specificity, NPV, Accuracy | `il_accuracy()` | `accuracy.py:274-276` | ✅ FIXED |
| P4 metric | `il_accuracy()` | `accuracy.py:280` | ✅ FIXED |
| Phi / MCC | `il_accuracy()` | `accuracy.py:281-282` | ✅ FIXED |
| ROC curve | `il_roc()` | Via accuracy | Parity |
| Precision-Recall curve | `il_precision_recall()` | Via accuracy | Parity |
| Prediction errors (FP/FN) | `il_errors()` | `accuracy.py:447-591` | Parity |
| Completeness | `il_completeness()` | `completeness.py` | Parity |
| Unlinkables | `il_unlinkables()` | `unlinkables.py` | Parity (different calc) |
| Label from column | `labels_from_column()` | `accuracy.py:498` | Parity |
| Label from pairwise | `il_estimate_m_from_labels()` | `estimate_m_from_pairwise_labels()` | Parity |
| **Blocking-miss flag** | `il_accuracy()` `fn_blocking_miss` column | `found_by_blocking_rules` | ✅ FIXED |

### 8a. ~~Missing~~ Evaluation Metrics — FIXED

All splink evaluation metrics are now implemented in `il_accuracy()`:
F2, F0.5, specificity, NPV, accuracy, P4, and Phi/MCC. Integer overflow
guards added for large label sets. The `fn_blocking_miss` column counts
false negatives due to blocking rule misses.

### 8b. ~~Blocking-Miss Adjustment~~ — FIXED

`score_labeled_pairs()` now evaluates blocking conditions on each labeled
pair and returns a `found_by_blocking` flag. `il_accuracy()` uses this to
report `fn_blocking_miss` — the count of true matches missed by blocking
rules at each threshold. SQL path computes the flag inside the innermost
subquery where table aliases are in scope; R path evaluates column equality
directly.

### 8c. ~~U from Pairwise Labels~~ — NOT A GAP

splink does NOT have `estimate_u_from_pairwise_labels()`. It only has
`estimate_m_from_pairwise_labels()` (for m-parameters from labeled pairs) and
`estimate_u_using_random_sampling()` (random pairs). irelink already has both
equivalents: `il_estimate_m_from_labels()` and `il_estimate_u()`.

---

## 9. Visualization

| Feature | irelink | splink | Parity |
|---|---|---|---|
| Match weights chart | `autoplot(model)` | `match_weights_chart()` | ✅ |
| M/U parameters | `autoplot(model, type="parameters")` | `m_u_parameters_chart()` | ✅ |
| Match weights histogram | `autoplot(compared)` | `match_weights_histogram()` | ✅ |
| Waterfall | `il_waterfall()` / `autoplot(compared)` | `waterfall_chart()` | ✅ |
| ROC curve | `autoplot(il_roc(...))` | `roc_chart()` | ✅ |
| Precision-Recall | `autoplot(il_precision_recall(...))` | `precision_recall_chart()` | ✅ |
| Accuracy | `autoplot(il_accuracy(...))` | `accuracy_chart()` | ✅ |
| Completeness | `autoplot(il_completeness(...))` | `completeness_chart()` | ✅ |
| Unlinkables | `autoplot(il_unlinkables(...))` | `unlinkables_chart()` | ✅ |
| TF adjustment | `il_tf_chart()` | `tf_adjustment_chart()` | ✅ |
| Training history | `il_training_history()` | `_iteration_history` | ✅ |
| Data profile | `il_profile()` | `profile_data.py` | ✅ |
| Comparator score | `il_comparator_score()` | `similarity_analysis.py` | ✅ |
| Column transforms | `il_column_transforms()` | — | **irelink only** |
| **Labelling tool** | — | `labelling_tool.py` | Interactive HTML UI |
| **Cluster Studio** | — | `cluster_studio.py` | Interactive cluster explorer |
| **Comparison viewer** | — | `splink_comparison_viewer.py` | Interactive dashboard |
| **Threshold selector** | — | `threshold_selection_tool()` | Interactive threshold UI |

### 9a. Missing Interactive Tools

splink ships interactive HTML/JS tools that irelink lacks:

1. **Labelling tool** (`labelling_tool.py`): presents record pairs in an HTML
   interface for manual match/non-match labelling.
2. **Cluster Studio** (`cluster_studio.py`): interactive network visualisation
   of entity clusters.
3. **Comparison viewer** (`splink_comparison_viewer.py`): interactive dashboard
   showing comparison vector distributions.
4. **Threshold selector** (`threshold_selection_tool()`): interactive tool for
   choosing score thresholds.

These are productivity/exploration tools. irelink's ggplot2-based autoplot
methods cover the same analytical ground in a static-plot format more natural
for R users.

---

## 10. Real-Time / New Record Matching

| Feature | irelink | splink |
|---|---|---|
| Find matches to new records | `il_find_matches()` | `find_matches_to_new_records()` |
| Compare two records | `il_compare_records()` | `compare_records()` (`realtime.py`) |
| Model requirement | Requires trained `il_model` | Settings dict sufficient |
| SQL caching | — | `SQLCache` for repeated calls |

splink's `compare_records()` can work with just a settings dictionary — no
Linker object needed. It also caches compiled SQL templates for repeated calls
with different records, useful in production scoring pipelines.

irelink's `il_compare_records()` requires a trained `il_model` (or at minimum
an `il_spec`). The model can be loaded from a saved file via `il_load()`.

---

## 11. SQL Generation Details

### 11a. Great Circle Distance

irelink uses haversine (ASIN); splink uses spherical law of cosines (ACOS).

irelink (`R/cl_domain.R`):
```sql
2 * 6371 * ASIN(SQRT(
  POWER(SIN(RADIANS((r.lat - l.lat) / 2)), 2) +
  COS(RADIANS(l.lat)) * COS(RADIANS(r.lat)) *
  POWER(SIN(RADIANS((r.long - l.long) / 2)), 2)
)) <= threshold
```

splink (`comparison_level_sql.py`):
```sql
ACOS(CASE WHEN x > 1 THEN 1 WHEN x < -1 THEN -1 ELSE x END) * 6371 <= threshold
```

The haversine formula is **more numerically robust** — its argument stays in
[0, 1] naturally, while splink's ACOS approach requires explicit clipping to
[-1, 1] because floating-point rounding can push the argument outside that
range. Both are mathematically equivalent.

### 11b. Gamma Encoding

- irelink: 0 for both null and else levels; null is a separate gamma level
  via `cl_null()` when explicitly added.
- splink: -1 for NULL, 0 for else, with null always as the first level.

Both are internally consistent with their respective EM and scoring code.

### 11c. DuckDB Function Names

All string distance function names match between both packages: `levenshtein`,
`damerau_levenshtein`, `jaro_similarity`, `jaro_winkler_similarity`, `jaccard`,
`array_cosine_similarity`, `list_intersect`, `regexp_extract`.

Only difference: splink uses `list_transform` for pairwise array operations;
irelink uses `UNNEST` cross-join instead. Both produce equivalent results.

---

## 12. Settings / Configuration

| Feature | irelink | splink |
|---|---|---|
| Link type | Inferred from 1 vs 2 tables | Explicit: `dedupe_only`, `link_only`, `link_and_dedupe` |
| Unique ID column | Always `unique_id` | Configurable via `unique_id_column_name` |
| Source dataset column | Via `source_dataset` parameter | Configurable via `source_dataset_column_name` |
| Column prefix (gamma) | `gamma_` (hardcoded) | Configurable `comparison_vector_value_column_prefix` |
| Retain matching columns | `include_fields` parameter | `retain_matching_columns` setting |
| Retain intermediate cols | — | `retain_intermediate_calculation_columns` |
| Additional columns | — | `additional_columns_to_retain` |
| Model serialization | `il_save()` / `il_load()` via RDS | JSON settings dict |

---

## 13. Backend Support

| Backend | irelink | splink |
|---|---|---|
| DuckDB | ✅ Primary | ✅ Primary |
| PostgreSQL | ✅ | ✅ |
| SQLite | ✅ (limited; no fuzzy SQL) | ✅ (limited) |
| Spark | — | ✅ |
| Databricks | — | ✅ |
| Athena (AWS) | — | ✅ |

Spark, Databricks, and Athena are enterprise-scale backends not typical for R
workflows. irelink targets DuckDB and PostgreSQL as first-class backends.

---

## 14. Summary: Genuine Remaining Gaps in irelink

### Core Algorithm Gaps

| Feature | splink Source | Status |
|---|---|---|
| ~~**TF during EM**~~ | `expectation_maximisation.py:290-297` | **FIXED** — `estimate_without_tf=FALSE` enables per-pair TF in EM (see §4a) |
| ~~**One-to-one clustering (iterative)**~~ | `one_to_one_clustering.py:103-338` | **FIXED** — iterative algorithm with dataset constraint re-evaluation (see §7b) |

### Blocking Gaps

| Feature | splink Source | Status |
|---|---|---|
| **Cost-optimised rule suggestion** | `optimise_cost_of_brs.py:123-218` | Gap — multi-objective optimisation over candidate rules |

### Interactive Tools

| Feature | splink Source | Impact |
|---|---|---|
| **Labelling tool** | `labelling_tool.py` | Manual labelling UI; productivity tool |
| **Cluster Studio** | `cluster_studio.py` | Interactive cluster exploration |
| **Comparison viewer** | `splink_comparison_viewer.py` | Interactive distribution dashboard |

### Minor

| Feature | splink Source | Status |
|---|---|---|
| **Configurable column names** | `settings.py` | `unique_id` is hardcoded |
| **`retain_intermediate_calculation_columns`** | `settings.py` | Debug output of intermediate BF columns |

### Previously Identified — Now Fixed or Resolved

| Feature | Resolution |
|---|---|
| TF during EM | ✅ FIXED — `estimate_without_tf=FALSE` enables per-pair TF in EM E-step |
| One-to-one clustering (iterative) | ✅ FIXED — `solve_one_to_one_sql()` / `solve_one_to_one_r()` with iterative constraint re-evaluation |
| EM column deactivation | ✅ FIXED — `il_estimate_em()` auto-removes comparisons overlapping with blocking columns |
| EM blocking-adjusted prior | ✅ FIXED — prior BF multiplied by deactivated comparisons' exact-match BFs |
| Blocking-miss accuracy | ✅ FIXED — `fn_blocking_miss` column in `il_accuracy()` |
| Additional metrics (F2, F0.5, MCC, P4, etc.) | ✅ FIXED — all added to `il_accuracy()` |
| Preceding-rule dedup | ✅ FIXED — `AND NOT (prior_rule)` in `build_gamma_query()` |
| `tf_adjustment_weight` | ✅ FIXED — `il_compare(tf_adjustment_weight=)` |
| `tf_minimum_u_value` | ✅ FIXED — `il_compare(tf_minimum_u_value=)` |
| `.try_parse_timestamp()` | ✅ FIXED — `il_try_parse_timestamp()` |
| Cumulative blocking analysis | Not a gap — `il_count_pairs()` + `autoplot(type='additional')` already provides this |
| U from pairwise labels | Not a gap — splink only has `estimate_m_from_pairwise_labels()`, not u |

---

## 15. Summary: irelink Improvements over splink

| Feature | irelink Source | Notes |
|---|---|---|
| **Haversine (ASIN) formula** | `R/cl_domain.R` | More numerically robust than splink's ACOS |
| **Phonetic transforms** | `R/il_phonetic.R` | Built-in soundex, metaphone, dmetaphone |
| **Phonetic blocking** | `R/il_block_on.R` | `.transform = il_soundex` directly in blocking |
| **US ZIP code comparison** | `R/cl_domain.R` | Domain-specific SCF fallback |
| **`cl_domain()`** | `R/cl_domain.R` | Domain extraction comparison |
| **Transform composition** | `R/il_column_transforms.R` | `il_transform(f1, f2)` chains |
| **`block_from_labels()`** | `R/il_suggest_blocking.R` | Derive blocking effectiveness from labeled data |
| **Prior derivation** | `R/il_estimate_em.R:277-281` | Derive prior from trained parameters post-EM |
| **Laplace smoothing** | `R/il_estimate_em.R:206` | Prevents zero m/u estimates |
| **Aggregated-pattern EM** | `R/utils-em.R` | EM on ~100 patterns, not millions of pairs |
| **Score missing edges** | `R/il_score_missing_edges.R` | Score within-cluster pairs missed by blocking |
| **CC max-iterations** | `R/utils-cc.R` | Safety valve prevents infinite loops |
| **Miles support** | `R/cl_distance_km.R` | `mi()` unit in addition to `km()` |
| **Pipe-based API** | All `il_*` functions | Idiomatic R; no OOP ceremony |
| **ggplot2 autoplot** | `R/autoplot.R` | Native R plotting ecosystem |
