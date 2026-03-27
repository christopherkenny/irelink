# 07 — Features for Later

> Gap analysis between splink's ~233 functions and irelink's 71 exports.
> Features listed here are intentionally deferred from the initial build.
> See `03-splink-functions.md` for the full splink catalog and
> `05-file-function-structure.md` for what irelink already covers.

---

## Coverage Summary

The initial irelink stub set covers the **complete core pipeline**:

```
spec → model → train → predict → cluster → evaluate → visualise
```

along with exploration tools, comparison helpers, serialization, and demo
data. Four functions were added during this audit to fill core gaps:

| New stub | Covers splink feature | Rationale |
|----------|----------------------|-----------|
| `il_deterministic_link()` | `linker.inference.deterministic_link()` | Exact-match linking without training is a common first workflow |
| `il_estimate_m_from_column()` | `linker.training.estimate_m_from_label_column()` | Label-column training is a distinct interface from pairwise labels |
| `il_cleanup()` | `linker.table_management.delete_tables_created_by_splink_from_db()` | Temporary-table cleanup is a practical necessity for SQL backends |
| `il_unlinkables()` | `linker.evaluation.unlinkables_chart()` | Unlinkables curve is a core diagnostic for threshold selection |

**Current total: 47 files, 71 exports.**

Everything below is deferred — not because it is unimportant, but
because it is not required for a functional v1 that covers the main
record-linkage workflow.

---

## 1 Column Transformers

**Splink feature:** `ColumnExpression` — a chainable class providing
`.lower()`, `.substr()`, `.regex_extract()`, `.nullif()`,
`.try_parse_date()`, etc. Applied to columns before comparison.

**Why deferred:** In idiomatic R, column pre-processing is handled
upstream with `dplyr::mutate()`. When using a database backend, dbplyr
translates `tolower()`, `substr()`, etc. into SQL automatically. This
means the typical R workflow is:

```r
tbl(con, "data") |>
  mutate(name_clean = tolower(name)) |>
  collect()
```

rather than embedding transforms inside the comparison specification. If
demand arises for in-spec transforms, a `transform` argument could be
added to `il_compare()` later:

```r
il_compare(name, cl_jaro_winkler(0.9), transform = tolower)
```

**Priority:** Medium. Revisit after v1 if users find dbplyr
pre-processing insufficient.

---

## 2 Blocking Optimisation Tools

**Splink features:**

| Function | Description |
|----------|-------------|
| `n_largest_blocks()` | Identify the n blocking-key values that produce the most comparisons |
| `suggest_blocking_rules()` | Heuristic optimiser that balances comparison count against field coverage |
| `find_blocking_rules_below_threshold_comparison_count()` | Recursive search for column combinations under a comparison-count ceiling |
| `block_from_labels()` | Build blocked pairs from a manually curated labels table |

**Why deferred:** These are power-user tools for tuning blocking
strategies on large datasets. `il_count_pairs()` covers the basic "how
many pairs does this rule generate?" question. The optimisation layer can
be added once the core blocking engine is solid.

**Priority:** Medium. Useful for large-scale production linkage.

---

## 3 Advanced Blocking Variants

**Splink features:**

| Class | Description |
|-------|-------------|
| `SaltedBlockingRule` | Adds random-salt partitioning for parallelism |
| `ExplodingBlockingRule` | Handles array columns by exploding them first |

**Why deferred:** These are performance-oriented extensions for
distributed backends (Spark, Athena). The base `BlockingRule` handles
all common cases. Salting and exploding can be added when Spark/Athena
backends are prioritised.

**Priority:** Low. Only relevant for distributed backends.

---

## 4 Label-Column Evaluation Variants

**Splink features:**

| Function | Description |
|----------|-------------|
| `prediction_errors_from_labels_column()` | False positives/negatives using a ground-truth column |
| `accuracy_analysis_from_labels_column()` | Accuracy charts driven by a label column |

**Why deferred:** The pairwise-labels variants (`il_errors()`,
`il_accuracy()`, `il_roc()`, `il_precision_recall()`) cover the same
analytical ground. The label-column variants are convenience wrappers
that derive pairwise labels from a column — easy to add as thin wrappers
once the core evaluation functions are working.

**Priority:** Low. Convenience layer over existing functions.

---

## 5 Visualisation — Parameter Comparisons

**Splink features:**

| Function | Description |
|----------|-------------|
| `parameter_estimate_comparisons_chart()` | Compare parameter estimates across different training runs |
| `tf_adjustment_chart()` | Show how term-frequency adjustments shift match weights |
| `match_weights_interactive_history_chart()` | Interactive match-weight history with iteration slider |
| `m_u_parameters_interactive_history_chart()` | Interactive m/u history with iteration slider |

**Why deferred:** `il_weights()`, `il_parameters()`, and
`il_training_history()` already return the underlying data as tibbles.
Users can build any comparison or interactive chart from those tibbles
using ggplot2 + plotly. Dedicated convenience functions for these
specific chart types are not essential for v1.

**Priority:** Low. Data is already accessible.

---

## 6 Interactive Dashboards

**Splink features:**

| Function | Description |
|----------|-------------|
| `comparison_viewer_dashboard()` | Interactive HTML dashboard with comparison vectors and example records |
| `cluster_studio_dashboard()` | Interactive HTML dashboard for exploring clustered records |
| `labelling_tool_for_specific_record()` | Standalone HTML labelling dashboard for one record's candidate matches |

**Why deferred:** Splink bundles these as Vega-Lite / HTML applications.
In R, interactive tools are built with Shiny. Building Shiny apps is a
separate project scope and would ideally be a companion package (e.g.,
`irelink.shiny`) rather than part of the core.

Alternatively, lightweight interactive exploration can be achieved via:
- `plotly::ggplotly()` for interactive charts
- `DT::datatable()` for record browsing
- `reactable` for cluster exploration

**Priority:** Low. Separate Shiny companion package recommended.

---

## 7 String Similarity — Batch and Phonetic

**Splink features:**

| Function | Description |
|----------|-------------|
| `comparator_score_df()` | Similarity scores for a list of string pairs (batch) |
| `comparator_score_chart()` | Heatmap of string-similarity scores |
| `comparator_score_threshold_chart()` | Heatmap filtered by thresholds |
| `phonetic_transform()` | Soundex, Metaphone, Double Metaphone |
| `phonetic_transform_df()` | Phonetic transforms for a list of strings |
| `phonetic_match_chart()` | Chart of phonetic-match results |

**Why deferred:** `il_string_similarity()` covers the single-pair case.
Batch scoring is straightforward with `purrr::map2()`. Phonetic
transforms are available in the `phonics` R package and can be used
independently.

**Priority:** Low. Covered by existing R packages.

---

## 8 Multi-Threshold Clustering

**Splink feature:**
`cluster_pairwise_predictions_at_multiple_thresholds()` — run connected-
components clustering at several thresholds for comparison.

**Why deferred:** `il_cluster()` supports a single threshold. Running it
at multiple thresholds is a `purrr::map()` call:

```r
thresholds <- c(0.7, 0.8, 0.9, 0.95)
purrr::map(thresholds, \(t) il_cluster(pairs, threshold = t))
```

A dedicated function adds little value.

**Priority:** Very low.

---

## 9 Table Management

**Splink features:**

| Function | Description |
|----------|-------------|
| `register_table()` | Register external data as a backend table |
| `compute_tf_table()` | Compute and persist a term-frequency lookup table |
| `register_term_frequency_lookup()` | Supply a pre-computed TF table |
| `register_table_input_nodes_concat_with_tf()` | Pre-computed concatenated input table |
| `register_table_predict()` | Pre-computed prediction table |
| `register_labels_table()` | Register labelled pairs |
| `invalidate_cache()` | Clear result cache |

**Why deferred:** In R, `DBI::dbWriteTable()` and
`dplyr::copy_to()` handle table registration. Term-frequency tables
are computed internally by `cl_exact(term_frequency = TRUE)` at model
creation time (see `compute_tf_tables()` in `utils-tf.R`).
`il_cleanup()` (now stubbed) covers cache/table cleanup. The remaining
register functions are Python-specific workflow steps that do not
translate directly to idiomatic R.

**Priority:** Very low. DBI and dplyr already provide the primitives.

---

## 10 Niche Comparison Levels

**Splink features not yet mapped to `cl_*()` helpers:**

| Level | Description |
|-------|-------------|
| `LiteralMatchLevel` | Match against a hard-coded literal value |
| `ArraySubsetLevel` | One array is a subset of another |
| `PairwiseStringDistanceFunctionLevel` | Best pairwise distance between elements of two arrays |
| `AbsoluteTimeDifferenceLevel` | Time difference (separate from date) |
| `DistanceFunctionLevel` | Arbitrary SQL distance function |

**Why deferred:** `cl_custom()` can express any of these as raw SQL.
Dedicated helpers can be added if users frequently need them.
`DistanceFunctionLevel` is effectively `cl_custom()`.

**Priority:** Low. `cl_custom()` is the escape hatch.

---

## 11 Testing Utilities

**Splink features:**

| Function | Description |
|----------|-------------|
| `is_in_level()` | Test whether literal values satisfy a comparison level's SQL condition |
| `comparison_vector_value()` | Compute the comparison-vector value for literal records against a comparison |

**Why deferred:** These are developer-facing debugging tools, useful for
writing tests for the package itself. They should be added as internal
helpers during the implementation stage.

**Priority:** Medium for package development. Not user-facing.

---

## 12 Demo Label Datasets

**Splink feature:** `SplinkDataSetLabels` — separate accessor for
ground-truth label tables matching the demo datasets.

**Why deferred:** `il_demo()` can be extended to accept label dataset
names (e.g., `il_demo("fake_1000_labels")`). No separate function
needed.

**Priority:** Low. Extend `il_demo()` when evaluation functions are
implemented.

---

## 13 Raw SQL Escape Hatch

**Splink feature:** `linker.misc.query_sql()` — run raw SQL against the
backend.

**Why deferred:** R users already have `DBI::dbGetQuery(con, sql)`. No
wrapper needed.

**Priority:** Not needed.

---

## 14 Batched / Incremental Retraining

**Splink feature:** None — splink does not support true incremental or
streaming parameter updates either.

**Production workflow (now supported):** The recommended pattern for both
splink and irelink is: train once → save → load with new data → predict.
Retrain from scratch only when data distribution changes materially.

The `il_attach()` function (added in sprint 10) closes this gap:

```r
# Train and save
model <- il_model(df, spec = spec, con = con) |>
  il_estimate_u() |>
  il_estimate_em(block_on(name))
il_save(model, "trained_model.json")

# Later: load and apply to fresh data
loaded <- il_load("trained_model.json")
con2 <- DBI::dbConnect(duckdb::duckdb())
model2 <- il_attach(loaded, new_data, con = con2)
pairs <- predict(model2)

# Optional: warm-start retraining on new data
model2 <- il_estimate_em(model2, block_on(name))
```

**Status:** Implemented. No further work needed.

---

## Priority Summary

| Priority | Features |
|----------|----------|
| **Medium** | Column transformers (§1), Blocking optimisation (§2), Testing utilities (§11) |
| **Low** | Label-column evaluation (§4), Param comparison charts (§5), Interactive dashboards (§6), Batch string similarity / phonetics (§7), Multi-threshold clustering (§8), Table management (§9), Niche comparison levels (§10), Demo labels (§12) |
| **Very low** | Advanced blocking variants (§3), Raw SQL wrapper (§13) |

---

## Recommendation

The current 71-export stub set is **sufficient for a complete v1**. The
core pipeline (spec → model → train → predict → cluster → evaluate →
visualise) is fully represented. The features listed here are
enhancements, convenience wrappers, and advanced capabilities that can
be added incrementally after the core is working.

The highest-priority gap is **column transformers** (§1). If users need
SQL-level column pre-processing that dbplyr cannot express, a `transform`
argument on `il_compare()` would be the cleanest addition.
