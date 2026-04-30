# Package surface review: irelink vs splink

## Overall character

irelink is a faithful idiomatic R translation. The conceptual model is identical
(Fellegi-Sunter, EM, blocking, clustering), but the API shape differs by language
idiom: splink uses an OO `Linker` object where everything lives as methods;
irelink separates the declarative spec (`il_spec`) from the trained model
(`il_model`) and uses free functions, which is more idiomatic R.

## What irelink has that splink has

| Capability | splink | irelink |
|---|---|---|
| Core estimation (u, EM, prior) | `estimate_u_using_random_sampling()`, `estimate_parameters_using_expectation_maximisation()`, `estimate_probability_two_random_records_match()` | `il_estimate_u()`, `il_estimate_em()`, `il_estimate_prior()` |
| Prediction | `linker.predict()` | `predict(model)` |
| Clustering | `cluster_pairwise_predictions_at_threshold()` | `il_cluster()` |
| Eval metrics | `precision_and_recall()`, `cluster_metrics()` | `il_accuracy()`, `il_roc()`, `il_precision_recall()`, `il_cluster_confusion_matrix()` — actually broader |
| Blocking analysis | `analyse_blocking_rule()` | `il_count_pairs()`, `il_largest_blocks()` |
| Waterfall chart | `waterfall_chart()` | `il_waterfall()` |
| TF adjustment | `register_term_frequency_table()` | `il_register_tf()` |
| Data profiling | `profile_columns()`, `completeness_chart()` | `il_profile()`, `il_completeness()` |
| Save/load | settings JSON | `il_save()` / `il_load()` |
| Semi-supervised m | `estimate_m_from_label_column()`, `estimate_m_from_pairwise_labels()` | `il_estimate_m_from_labels()`, `il_estimate_m_from_column()` |

## What splink has that irelink appears to lack

1. **`compare_two_records()`** — Real-time single-pair scoring without a batch
predict. Useful for debugging and interactive exploration. irelink has
`il_waterfall()` which is adjacent, but it works on already-scored pairs.

2. **`find_matches_to_new_records()`** — Incremental/streaming: link new records
into an existing trained model without re-scoring everything. irelink has
`il_attach()` for model reuse but it re-predicts all pairs.

3. **`cluster_studio_dashboard()`** — Interactive HTML cluster visualization for
spot-checking. irelink has `autoplot()` methods but no equivalent interactive
dashboard.

4. **`threshold_selection_tool()`** — Interactive tool to pick a threshold vs.
precision/recall curve. irelink has `il_roc()` and `il_precision_recall()` which
serve the same purpose via ggplot, but not interactive.

5. **`ColumnExpression` class** — A way to pass arbitrary column transformations
into blocking rules inline. irelink has the `transform` argument on
`il_block_on()`, which is similar but less composable.

## What irelink has beyond splink

- **`il_suggest_blocking()`** — Auto-suggest good blocking rules from the data;
splink has no equivalent.
- **`il_unlinkables()`** — Identify records that structurally can't match under
current blocking; splink has no equivalent.
- **`il_errors()`** — Explicit FP/FN enumeration with filtering; splink surfaces
this only through cluster diagnostics.
- **`il_string_similarity()`**, **`il_comparator_score()`**,
**`il_comparator_threshold_chart()`**, **`il_phonetic_chart()`** — Richer
pre-modeling comparison analysis.
- **`il_find_matches()` / `il_deterministic_link()`** — Deterministic linking as
a first-class operation, not just a training tool.

## API design observations

**Strength:** The `il_spec` / `il_model` separation is actually better than
splink's monolithic `Linker`. It means you can share a spec across multiple
datasets or models without re-specifying everything.

**Potential friction point:** splink's `block_on()` works the same in both
training and prediction context. irelink has `block_on()` (for training only) vs.
`il_block_on()` (for prediction, added to spec) — the namespace distinction may
confuse users coming from splink.

**Naming:** `cl_*` for comparison levels and `il_*` for model operations is clean
and consistent. splink's `comparison_library.*` is more discoverable via
autocomplete in Python but harder to type.

**Missing interactivity:** splink's interactive HTML charts
(`cluster_studio_dashboard`, `threshold_selection_tool`) are a significant UX
advantage that irelink's static ggplot2 outputs don't match. Given R's ecosystem,
Shiny-based equivalents or htmlwidgets would be the natural path.

## Bottom line

Functionally irelink covers ~85–90% of splink's surface with some genuine
additions (blocking suggestion, unlinkables, richer string similarity diagnostics).
The main gaps are the interactive/incremental features: real-time single-pair
scoring, incremental `find_matches_to_new_records`, and the interactive cluster
dashboard.
