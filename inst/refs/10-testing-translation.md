# 10 — Testing Translation: splink → irelink

> Maps every relevant splink test to an irelink testthat test.
> Organises 182 tests across 26 files, tagged by sprint.
>
> **Key files:**
>
> - `tests/testthat/setup.R` — defines `current_sprint` and `skip_if_sprint_lt()`
> - `tests/testthat/test-*.R` — 26 test files covering all 10 sprints
>
> **Cross-references:**
>
> - `08-sprints.md` — sprint sequence and function tables
> - `09-implementation-plan.md` — Stage 3 test plan (§3b–3k)
> - `04-irelink-core-interface.md` — interface design (expected behaviour)

---

## 1. Methodology

### 1.1 splink test inventory

The splink test suite contains **68 test files** with **340+ test
functions** across these categories:

| Category | splink files | splink tests |
|----------|:----------:|:----------:|
| Comparison levels & composition | 12 | ~50 |
| Blocking & analysis | 6 | ~30 |
| EM training & convergence | 7 | ~25 |
| Clustering & graph metrics | 6 | ~20 |
| Evaluation & accuracy | 1 | 12 |
| End-to-end examples (per-backend) | 5 | ~15 |
| Data profiling & completeness | 2 | ~11 |
| Inference (predict, compare, find) | 4 | ~10 |
| Visualization & charts | 3 | ~8 |
| Caching & table management | 2 | ~15 |
| Settings & configuration | 3 | ~10 |
| Column handling & SQL transforms | 5 | ~15 |
| Term frequency | 2 | ~6 |
| UDFs (Spark/Postgres) | 2 | ~6 |
| Backward compatibility (splink2) | 1 | 6 |
| Other (regex, salting, datasets) | 5 | ~5 |

### 1.2 Translation decisions

1. **Translated:** Tests covering core features that map to irelink
   functions — comparison levels, blocking, EM training, prediction,
   clustering, evaluation, visualization, serialisation, data
   exploration, and demo data.

2. **Not translated** (deferred per `07-features-for-later.md`):
   - Caching/table management (15 tests) — internal optimisation,
     not part of v1
   - Backend-specific UDFs (10 tests) — Spark and Postgres UDFs
     are deferred; DuckDB is tested via integration
   - Backward compatibility with splink2 (6 tests) — irrelevant
     for a new R package
   - Salting/exploding blocking (5 tests) — advanced blocking
     optimisation, deferred
   - Term frequency adjustments (6 tests) — deferred to later
     sprints per `07-features-for-later.md`
   - Settings validation internals (6 tests) — Python-specific
     dict validation; R uses S3 validators instead
   - Column expression / SQL transform internals (15 tests) —
     Python-specific column abstraction; R uses tidyselect
   - Interactive dashboards / cluster studio (3 tests) — Shiny,
     deferred

3. **Adapted:** Tests were rewritten to use irelink's pipe-friendly
   API rather than splink's class-method pattern. For example,
   splink's `linker.training.estimate_parameters_using_expectation_maximisation()`
   becomes `model |> il_estimate_em()`.

4. **Skip mechanism:** Every test calls `skip_if_sprint_lt(N)` where
   N is the sprint number. `current_sprint` is set in `setup.R`.
   Incrementing it un-gates that sprint's tests.

### 1.3 Test conventions

- **No loops around expectations.** Each `expect_*()` is a separate,
  traceable assertion. Where splink uses parametrised tests, irelink
  uses separate `test_that()` blocks or multiple assertions in one
  block.
- **DBI connections** use RSQLite (`:memory:`) with `withr::defer()`
  cleanup. DuckDB is noted in `Suggests` but not required.
- **Demo data** via `il_demo("fake_1000")` — Sprint 4 must provide
  this before Sprint 5+ integration tests can run.

---

## 2. Sprint → Test File Mapping

| Sprint | Test files | Tests | splink sources |
|:------:|-----------|:-----:|----------------|
| 1 | `test-il_spec.R`, `test-unit-helpers.R`, `test-classes.R` | 20 | No direct equivalent; structural contract tests |
| 2 | `test-cl-similarity.R`, `test-cl-levels.R`, `test-cl-domain.R` | 53 | `test_comparison_level.py`, `test_comparison_level_lib.py`, `test_comparison_level_composition.py`, `test_comparison_template_lib.py`, `test_compound_comparison_levels.py`, `test_date_levels_and_comparisons.py`, `test_km_distance_level.py`, `test_array_columns.py` |
| 3 | `test-il_compare.R`, `test-il_block_on.R` | 19 | `test_blocking.py`, `test_blocking_rule_composition.py`, `test_columns_selected.py`, `test_settings_validation.py` |
| 4 | `test-il_demo.R`, `test-il_string_similarity.R` | 14 | `test_splink_datasets.py` |
| 5 | `test-sql-generate.R`, `test-il_completeness.R`, `test-il_profile.R`, `test-il_count_pairs.R` | 20 | `test_linker_variants.py`, `test_blocking.py`, `test_blocking_rule_composition.py`, `test_completeness.py`, `test_profile_data.py`, `test_analyse_blocking.py`, `test_total_comparison_count.py` |
| 6 | `test-il_model.R` | 8 | `test_full_example_duckdb.py`, `test_settings_validation.py`, `test_caching_tables.py` |
| 7 | `test-il_estimate.R`, `test-il_weights.R` | 14 | `test_u_train.py`, `test_expectation_maximisation.py`, `test_correctness_of_convergence.py`, `test_estimate_prob_two_rr_match.py`, `test_m_train.py` |
| 8 | `test-predict.R`, `test-il_deterministic_link.R`, `test-il_waterfall.R` | 11 | `test_full_example_duckdb.py`, `test_full_example_sqlite.py`, `test_full_example_deterministic_link.py`, `test_compare_two_records.py`, `test_find_new_matches.py` |
| 9 | `test-il_cluster.R`, `test-il_graph_metrics.R` | 11 | `test_clustering.py`, `test_cluster_using_single_best_links.py`, `test_cc_random_graphs.py`, `test_cluster_at_multiple_thresholds.py`, `test_graph_metrics.py` |
| 10 | `test-il_accuracy.R`, `test-il_roc.R`, `test-autoplot.R`, `test-il_save.R` | 12 | `test_accuracy.py`, `test_charts.py`, `test_full_example_duckdb.py` |
| 8+ | `test-pipeline-integration.R` | 3 | 09-implementation-plan §6b (tidyverse integration) |
| **Total** | **27 files** | **196** | |

---

## 3. Detailed Test Inventory

### 3.1 Sprint 1 — Foundation (20 tests)

#### `test-il_spec.R` (4 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `il_spec()` creates an il_spec object | — | S3 class creation |
| 2 | `is_il_spec()` returns TRUE/FALSE correctly | — | Type checking |
| 3 | `print.il_spec()` produces output | — | Print method |
| 4 | Fresh spec has empty comparisons and rules | — | Initial state |

#### `test-unit-helpers.R` (9 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `days(30)` creates tagged value | — | Constructor |
| 2 | `months(6)` creates tagged value | — | Constructor |
| 3 | `years(10)` creates tagged value | — | Constructor |
| 4 | `km(5)` creates tagged value | — | Constructor |
| 5 | `mi(10)` creates tagged value | — | Constructor |
| 6 | Non-numeric input rejected | — | Validation |
| 7 | Negative values rejected | — | Validation |
| 8 | Print output is informative | — | Display |
| 9 | Bare numerics compatible | — | Backward compat |

#### `test-classes.R` (7 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `new_il_spec()` creates valid structure | — | Constructor |
| 2 | `validate_il_spec()` accepts well-formed | — | Validator |
| 3 | `validate_il_spec()` rejects malformed | — | Validator |
| 4 | `new_il_model()` creates valid structure | — | Constructor |
| 5 | `validate_il_model()` rejects malformed | — | Validator |
| 6 | `new_il_compared()` creates valid structure | — | Constructor |
| 7 | `validate_il_compared()` rejects malformed | — | Validator |

### 3.2 Sprint 2 — Comparison Helpers (53 tests)

#### `test-cl-similarity.R` (25 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `cl_exact()` creates level object | `test_comparison_level.py` | Constructor |
| 2 | `cl_exact()` accepts TF flag | `test_comparison_level.py` | Options |
| 3 | `cl_jaro_winkler()` descending thresholds | `test_comparison_level_lib.py` | Ordering |
| 4 | `cl_jaro_winkler()` warns on non-descending | `test_comparison_level_lib.py` | Validation |
| 5 | `cl_jaro_winkler()` single threshold | — | Basic usage |
| 6 | `cl_jaro()` creates jaro level | — | Constructor |
| 7 | `cl_levenshtein()` stores distances | `test_comparison_level_lib.py::test_levenshtein_level` | Constructor |
| 8 | `cl_damerau_levenshtein()` constructor | `test_comparison_level_lib.py::test_damerau_levenshtein_level` | Constructor |
| 9 | `cl_jaccard()` constructor | — | Constructor |
| 10 | `cl_cosine()` constructor | `test_comparison_level_lib.py::test_cosine_similarity_level` | Constructor |
| 11 | `cl_numeric_diff()` thresholds | `test_comparison_level_lib.py::test_absolute_difference` | Constructor |
| 12 | `cl_pct_diff()` thresholds | `test_comparison_level_lib.py::test_perc_difference` | Constructor |
| 13 | `cl_date_diff()` with unit helpers | `test_date_levels_and_comparisons.py` | Integration |
| 14 | `cl_date_diff()` with bare numerics | `test_date_levels_and_comparisons.py` | Bare-numeric compat |
| 15 | `cl_date_diff()` mixed metrics | `test_date_levels_and_comparisons.py::test_absolute_date_difference_at_thresholds` | Multi-metric |
| 16 | `cl_date_diff()` rejects negatives | `test_date_levels_and_comparisons.py::test_time_difference_error_logger` | Validation |
| 17 | `cl_date_diff()` rejects invalid metrics | `test_date_levels_and_comparisons.py::test_time_difference_error_logger` | Validation |
| 18 | `cl_distance_km()` constructor | `test_km_distance_level.py` | Constructor |
| 19 | `cl_distance_km()` bare numerics | `test_km_distance_level.py` | Bare-numeric compat |
| 20 | `cl_distance_km()` accepts miles | — | Unit conversion |
| 21 | `cl_array_intersect()` constructor | `test_array_columns.py::test_array_comparison_1` | Constructor |
| 22 | `cl_array_intersect()` rejects negatives | `test_array_columns.py` | Validation |
| 23 | `cl_custom()` stores SQL expression | — | Constructor |
| 24 | Similarity thresholds in [0, 1] | `test_date_levels_and_comparisons.py::test_time_difference_error_logger` | Validation |
| 25 | Distance thresholds non-negative | — | Validation |

#### `test-cl-levels.R` (17 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `cl_null()` sentinel | `test_comparison_level_composition.py` | Constructor |
| 2 | `cl_else()` fallback | `test_comparison_level_composition.py` | Constructor |
| 3 | `cl_levels()` nests children | `test_comparison_level_composition.py` | Composition |
| 4 | `cl_levels()` validates null-first | `test_comparison_level_composition.py` | Ordering |
| 5 | `cl_levels()` validates else-last | `test_comparison_level_composition.py` | Ordering |
| 6 | `cl_levels()` without null/else | — | Flexibility |
| 7 | `cl_and()` creates AND node | `test_comparison_level_composition.py::binary_composition_internals_AND` | Boolean |
| 8 | `cl_or()` creates OR node | `test_comparison_level_composition.py::binary_composition_internals_OR` | Boolean |
| 9 | `cl_not()` negates a level | `test_comparison_level_composition.py::test_not` | Boolean |
| 10 | `cl_and(null, null)` is null | `test_comparison_level_composition.py::test_null_level_composition` | Null propagation |
| 11 | `cl_or(null, null)` is null | `test_comparison_level_composition.py::test_null_level_composition` | Null propagation |
| 12 | `cl_not(null)` is not null | `test_comparison_level_composition.py::test_not` | Null propagation |
| 13 | `cl_and(exact, null)` is not null | `test_comparison_level_composition.py` | Null propagation |
| 14 | `cl_or()` with no args errors | `test_comparison_level_composition.py` | Validation |
| 15 | `cl_and()` with no args errors | `test_comparison_level_composition.py` | Validation |
| 16 | `cl_not()` with no args errors | `test_comparison_level_composition.py::test_not` | Validation |
| 17 | Nested: `cl_not(cl_or(...))` | `test_comparison_level_composition.py` | Deep nesting |

#### `test-cl-domain.R` (11 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `cl_name()` structure | `test_comparison_template_lib.py::test_name_comparison` | Constructor |
| 2 | `cl_name()` level count | `test_comparison_template_lib.py::test_name_comparison` | Structure |
| 3 | `cl_name()` ≡ manual composition | `test_comparison_template_lib.py::test_name_comparison` | Equivalence |
| 4 | `cl_email()` structure | `test_comparison_template_lib.py::test_email_comparison` | Constructor |
| 5 | `cl_email()` level count | `test_comparison_template_lib.py::test_email_comparison` | Structure |
| 6 | `cl_dob()` structure | `test_comparison_template_lib.py::test_date_of_birth_comparison_levels` | Constructor |
| 7 | `cl_dob()` level count | `test_comparison_template_lib.py::test_date_of_birth_comparison_levels` | Structure |
| 8 | `cl_postcode()` structure | `test_comparison_template_lib.py::test_postcode_comparison` | Constructor |
| 9 | `cl_postcode()` level count | `test_comparison_template_lib.py::test_postcode_comparison` | Structure |
| 10 | `cl_forename_surname()` structure | `test_comparison_template_lib.py::test_forename_surname_comparison` | Constructor |
| 11 | `cl_forename_surname()` level count | `test_comparison_template_lib.py::test_forename_surname_comparison` | Structure |

### 3.3 Sprint 3 — Spec Composition (19 tests)

#### `test-il_compare.R` (9 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns il_spec (pipe-friendly) | `test_new_comparison_levels.py` | Pipe contract |
| 2 | Two calls accumulate | — | Accumulation |
| 3 | Multiple calls never overwrite | — | Accumulation |
| 4 | Bare column name works | `test_columns_selected.py` | Tidyselect |
| 5 | `c()` for multiple columns | `test_columns_selected.py` | Tidyselect |
| 6 | Non-spec input errors | `test_settings_validation.py` | Type safety |
| 7 | Stores method with column | — | Internal state |
| 8 | Accepts domain bundles | `test_comparison_template_lib.py` | Integration |
| 9 | Print shows comparisons | — | Display |

#### `test-il_block_on.R` (10 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns il_spec | `test_blocking.py` | Pipe contract |
| 2 | Adds blocking rules | `test_blocking.py` | Accumulation |
| 3 | Multiple calls OR semantics | `test_blocking.py` | OR composition |
| 4 | Multi-column = AND within rule | `test_blocking_rule_composition.py` | AND composition |
| 5 | Non-spec input errors | — | Type safety |
| 6 | Print shows blocking rules | — | Display |
| 7 | `block_on()` is standalone | `test_blocking.py` | Standalone rule |
| 8 | `block_on()` single column | `test_blocking.py` | Basic usage |
| 9 | `block_on()` multi-column AND | `test_blocking_rule_composition.py` | AND composition |
| 10 | Full spec with pipes | — | Integration |

### 3.4 Sprint 4 — Demo Data & Strings (14 tests)

#### `test-il_demo.R` (6 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns tibble | `test_splink_datasets.py` | Data loading |
| 2 | Expected columns | `test_splink_datasets.py` | Schema |
| 3 | 1000 rows | `test_splink_datasets.py` | Size |
| 4 | No-arg lists datasets | — | Discovery |
| 5 | Invalid name errors | — | Validation |
| 6 | Link variant returns two tables | — | Link data |

#### `test-il_string_similarity.R` (8 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns tibble | — | Output structure |
| 2 | Expected metric columns | — | Schema |
| 3 | Identical strings → 1.0 | — | Edge case |
| 4 | Known JW scores | `test_comparison_level_lib.py` | Correctness |
| 5 | Different strings → low score | — | Correctness |
| 6 | Empty string handled | — | Edge case |
| 7 | NA handled | — | Edge case |
| 8 | Levenshtein known values | `test_comparison_level_lib.py::test_levenshtein_level` | Correctness |

### 3.5 Sprint 5 — SQL Engine & Exploration (20 tests)

#### `test-sql-generate.R` (9 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `cl_exact()` → equality SQL | `test_blocking.py` | SQL generation |
| 2 | `cl_jaro_winkler()` → CASE SQL | `test_linker_variants.py` | SQL generation |
| 3 | `cl_levenshtein()` → distance SQL | `test_linker_variants.py` | SQL generation |
| 4 | `cl_date_diff()` → date SQL | `test_linker_variants.py` | SQL generation |
| 5 | `block_on()` → equality SQL | `test_blocking.py` | SQL generation |
| 6 | Multiple rules → OR SQL | `test_blocking_rule_composition.py` | Composition |
| 7 | Multi-column → AND SQL | `test_blocking_rule_composition.py` | Composition |
| 8 | Dedupe join excludes self-pairs | `test_linker_variants.py::test_dedupe_only_join_condition` | Join SQL |
| 9 | Link join pairs across datasets | `test_linker_variants.py::test_link_only_two_join_condition` | Join SQL |

#### `test-il_completeness.R` (3 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns tibble with columns | `test_completeness.py::test_completeness_chart` | Output structure |
| 2 | Correct non-null percentages | `test_completeness.py` | Correctness |
| 3 | Fully-complete dataset → 100% | `test_completeness.py` | Edge case |

#### `test-il_profile.R` (3 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns value counts | `test_profile_data.py::test_profile_using_duckdb` | Output structure |
| 2 | All-null column handled | `test_profile_data.py::test_profile_null_columns` | Edge case |
| 3 | Multiple columns work | `test_profile_data.py` | Multi-column |

#### `test-il_count_pairs.R` (5 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Accurate dedupe pair count | `test_analyse_blocking.py::test_analyse_blocking_slow_methodology` | Correctness |
| 2 | Blocking reduces count | `test_analyse_blocking.py` | Blocking effect |
| 3 | Cartesian = n(n-1)/2 | `test_total_comparison_count.py::test_calculate_cartesian_dedupe_only` | Formula |
| 4 | Link cross-product | `test_total_comparison_count.py::test_calculate_cartesian_link_only` | Formula |
| 5 | Multiple rules reported | `test_analyse_blocking.py` | Multi-rule |

### 3.6 Sprint 6 — Model Creation (8 tests)

#### `test-il_model.R` (8 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Creates il_model object | `test_full_example_duckdb.py` | Creation |
| 2 | `is_il_model()` works | — | Type check |
| 3 | Missing column errors | `test_settings_validation.py::test_check_for_missing_settings_column` | Validation |
| 4 | `link_type="link"` requires two datasets | `test_linker_variants.py` | Validation |
| 5 | `link_type="link"` accepts two datasets | `test_full_example_duckdb.py::test_link_only` | Link mode |
| 6 | `print()` shows key info | `test_full_example_duckdb.py` | Display |
| 7 | `summary()` shows untrained | `test_full_example_duckdb.py` | Display |
| 8 | `il_cleanup()` removes temp tables | `test_caching_tables.py::test_table_deletions` | Cleanup |

### 3.7 Sprint 7 — Training (14 tests)

#### `test-il_estimate.R` (10 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `il_estimate_u()` sets u params | `test_u_train.py::test_u_train` | U estimation |
| 2 | U values are reasonable | `test_u_train.py::test_u_train` | Value range |
| 3 | `il_estimate_em()` updates params | `test_expectation_maximisation.py` | EM training |
| 4 | Empty blocking errors clearly | `test_expectation_maximisation.py::test_clear_error_when_empty_block` | Error handling |
| 5 | Multiple EM calls refine | `test_expectation_maximisation.py::test_estimate_without_term_frequencies` | Accumulation |
| 6 | Fixed probabilities preserved | `test_expectation_maximisation.py::test_fix_probabilities` | Fixed params |
| 7 | `il_estimate_prior()` valid probability | `test_estimate_prob_two_rr_match.py::test_prob_rr_match_dedupe` | Prior |
| 8 | Higher recall → higher prior | `test_estimate_prob_two_rr_match.py` | Recall effect |
| 9 | `il_estimate_m_from_labels()` works | `test_m_train.py::test_m_train` (method 2) | M from labels |
| 10 | `il_estimate_m_from_column()` works | `test_m_train.py::test_m_train` (method 1) | M from column |

#### `test-il_weights.R` (4 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Expected tibble columns | `test_charts.py::test_m_u_charts` | Output shape |
| 2 | One row per level | — | Row count |
| 3 | m/u in [0, 1] | `test_correctness_of_convergence.py` | Value range |
| 4 | Convergence history data | `test_compare_splink2.py` | Training trace |

### 3.8 Sprint 8 — Prediction (11 tests)

#### `test-predict.R` (5 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns il_compared tibble | `test_full_example_duckdb.py` | Output class |
| 2 | Required columns present | `test_full_example_duckdb.py` | Schema |
| 3 | Threshold filters pairs | `test_full_example_duckdb.py` | Filtering |
| 4 | Gamma columns present | `test_full_example_duckdb.py` | Comparison vectors |
| 5 | Probabilities in [0, 1] | `test_train_vs_predict.py` | Value range |

#### `test-il_deterministic_link.R` (2 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns exact-match pairs | `test_full_example_deterministic_link.py` | Correctness |
| 2 | No training required | `test_full_example_deterministic_link.py` | Independence |

#### `test-il_waterfall.R` (4 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Scores known pair | `test_compare_two_records.py::test_compare_two_records_1` | Pair scoring |
| 2 | Identical records → top gamma | `test_compare_two_records.py` | Edge case |
| 3 | Finds matches for new record | `test_find_new_matches.py::test_matches_work` | New-record matching |
| 4 | Contributions sum to total weight | — | Consistency |

### 3.9 Sprint 9 — Clustering (11 tests)

#### `test-il_cluster.R` (6 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Connected pairs → same cluster | `test_clustering.py::test_clustering` | Connected components |
| 2 | Threshold re-filters | `test_clustering.py` | Threshold |
| 3 | Empty predictions handled | `test_clustering.py::test_clustering_no_edges` | Edge case |
| 4 | Best-link limits per-source | `test_cluster_using_single_best_links.py::test_single_best_links_correctness_example_1` | Best-link |
| 5 | Ties handled in best_link | `test_cluster_using_single_best_links.py::test_single_best_links_ties` | Tie-breaking |
| 6 | Matches igraph components | `test_cc_random_graphs.py::test_small_erdos_renyi_graph` | Correctness |

#### `test-il_graph_metrics.R` (5 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Returns list of 3 tibbles | `test_graph_metrics.py::test_size_density_dedupe` | Output structure |
| 2 | Correct cluster sizes | `test_graph_metrics.py::test_metrics` | Size |
| 3 | Node degree computed | `test_graph_metrics.py::test_metrics` | Degree |
| 4 | Isolated nodes handled | `test_graph_metrics.py::test_size_density_dedupe` | Edge case |
| 5 | Cluster density correct | `test_graph_metrics.py::test_size_density_dedupe` | Density |

### 3.10 Sprint 10 — Evaluation, Visualisation, Serialisation (12 tests)

#### `test-il_accuracy.R` (3 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Correct TP/FP/TN/FN | `test_accuracy.py::test_truth_space_table_from_labels_column_dedupe_only` | Correctness |
| 2 | TP + FN = constant | `test_accuracy.py::test_truth_space_table` | Consistency |
| 3 | FP/FN pairs returned | `test_accuracy.py::test_prediction_errors_from_labels_table` | Error analysis |

#### `test-il_roc.R` (3 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | ROC tibble with fpr/tpr in [0,1] | `test_accuracy.py::test_roc_chart_dedupe_only` | Output shape |
| 2 | Precision/recall in [0,1] | — | Output shape |
| 3 | Unlinkables monotonically increase | — | Monotonicity |

#### `test-autoplot.R` (2 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | `autoplot(model)` → ggplot | `test_charts.py::test_m_u_charts` | Output class |
| 2 | `autoplot(pairs)` → ggplot | `test_charts.py` | Output class |

#### `test-il_save.R` (4 tests)

| # | Test | splink source | What it verifies |
|---|------|---------------|-----------------|
| 1 | Round-trip preserves params | `test_full_example_duckdb.py` (save/load) | Serialisation |
| 2 | Creates valid JSON | `test_full_example_duckdb.py` | Format |
| 3 | Non-existent file errors | — | Validation |
| 4 | Untrained model savable | — | Edge case |

---

## 4. Deferred splink tests (not translated)

These tests were reviewed and intentionally excluded from the
initial translation. They correspond to features deferred in
`07-features-for-later.md`.

| Category | splink tests | Count | Reason |
|----------|-------------|:-----:|--------|
| Caching / table management | `test_caching.py`, `test_caching_tables.py` | 15 | Internal optimisation; not in v1 |
| Spark UDFs | `test_spark_udfs.py` | 4 | Backend deferred |
| Postgres UDFs | `test_postgres_udfs.py` | 2 | Backend deferred |
| Backward compat (splink2) | `test_compare_splink2.py` | 6 | Not applicable |
| Salting / exploding blocking | `test_salting_len.py`, parts of `test_array_based_blocking.py` | ~5 | Advanced blocking, deferred |
| Term frequency adjustments | `test_term_frequencies.py`, `test_disable_tf_exact_match_detection.py` | ~6 | Deferred |
| Settings validation (dict) | `test_settings_validation.py` (most) | ~6 | Python-specific |
| Column expression / SQL transform | `test_column_expression.py`, `test_sql_transform.py`, `test_columns_used.py`, `test_input_column.py` | ~15 | Python abstraction layer |
| Cluster studio / dashboards | `test_cluster_studio.py`, `test_comparison_viewer_dashboard.py` | ~3 | Shiny deferred |
| Realtime / caching | `test_realtime.py` | 5 | Advanced inference, deferred |
| Score missing edges | `test_score_missing_edges.py` | 3 | Advanced inference, deferred |
| **Total deferred** | | **~70** | |

---

## 5. Test infrastructure

### `tests/testthat/setup.R`

```r
current_sprint <- 0L

skip_if_sprint_lt <- function(sprint) {
  testthat::skip_if(
    current_sprint < sprint,
    message = paste0("Sprint ", sprint, " not yet implemented (current: ", current_sprint, ")")
  )
}
```

**Usage:** When Sprint N is implemented, set `current_sprint <- N`
to un-gate those tests. All prior sprints' tests also run.

### Database connections

Tests in Sprints 5–10 require a DBI connection. They use:

```r
skip_if_not_installed("RSQLite")
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
withr::defer(DBI::dbDisconnect(con))
```

This avoids DuckDB (which hangs on this machine) while still
testing the SQL engine.

### Test data

Sprints 5–10 depend on `il_demo("fake_1000")` (Sprint 4). Smaller
hand-crafted data frames are used where possible to keep tests
fast and deterministic.

---

## 6. Summary

| Metric | Value |
|--------|------:|
| Test files created | 27 |
| Total `test_that()` blocks | 196 |
| splink test files reviewed | 68 |
| splink tests translated | ~180 |
| R-specific tests (from §6a/6b) | 14 |
| splink tests deferred | ~70 |
| Sprint coverage | All 10 sprints |

All 196 tests currently skip (`current_sprint = 0`). As each sprint
is implemented, increment `current_sprint` in `setup.R` to activate
that sprint's tests.

---

## 7. R-specific tests (from 09-implementation-plan §6a/6b)

After comparing all test suggestions in `09-implementation-plan.md`
against the translated test suite, 14 additional tests were added
to cover R-native concerns that splink's test suite would not cover.

### Added to existing files

**`test-il_compare.R` (Sprint 3):**

| # | Test | Source | What it verifies |
|---|------|--------|-----------------|
| 10 | `starts_with("addr_")` tidyselect | §3d | Column selection |
| 11 | `everything()` tidyselect | §6b | Column selection |
| 12 | `matches("name")` tidyselect | §6b | Column selection |

**`test-cl-similarity.R` (Sprint 2):**

| # | Test | Source | What it verifies |
|---|------|--------|-----------------|
| 26 | `cl_exact()` handles factor columns | §6a | R type safety |
| 27 | `cl_date_diff()` compatible with Date/POSIXct | §6a | R type safety |

**`test-il_model.R` (Sprint 6):**

| # | Test | Source | What it verifies |
|---|------|--------|-----------------|
| 9 | Zero-row data frame | §6a | R type safety |
| 10 | Single-row dedupe → zero pairs | §6a | R type safety |
| 11 | Factor columns in data | §6a | R type safety |

**`test-predict.R` (Sprint 8):**

| # | Test | Source | What it verifies |
|---|------|--------|-----------------|
| 6 | Known planted duplicates found | §3i | Correctness |
| 7 | dplyr verbs on il_compared | §6b | Tidyverse integration |
| 8 | il_compared prints like tibble | §6b | Tidyverse integration |

### New file: `test-pipeline-integration.R`

| # | Test | Sprint | Source | What it verifies |
|---|------|:------:|--------|-----------------|
| 1 | Full pipe chain: spec → predict | 8 | §6b | End-to-end |
| 2 | Full pipe chain through clustering | 9 | §6b | End-to-end |
| 3 | ggplot2 from il_weights() data | 10 | §6b | Tidyverse integration |

### Deferred to Stage 6

These tests from §6c–6e require working implementation and are not
appropriate for the pre-implementation test suite:

- **Snapshot tests** (§6d): `print.il_spec()`, `print.il_model()`,
  `summary.il_model()`, SQL snippets — need stable output to snapshot
- **Performance tests** (§6e): EM convergence < 30s, prediction < 30s,
  clustering < 10s — need working code to benchmark
- **Backend compatibility** (§6c): PostgreSQL, full DuckDB vs SQLite
  matrix — need backend abstraction layer working first
