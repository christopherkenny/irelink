# Tutorial Lessons: Datasets, Plots, and Diagnostics

This document captures what we learned by auditing splink's tutorials
(00–08), demo notebooks, and the rl-bootcamp workshop, then identifies
the datasets and features added to irelink as a result.

## Datasets

### Problem

The original `fake_1000` was procedurally generated with `set.seed()` in
package code — a practice that must never be used in R packages because
it affects the user's global RNG state.
The generated data also had no clear provenance link to splink's actual
demo data.

Splink ships 7 demo datasets (plus a labels file), all with ground-truth
columns: `fake_1000` (250 entities × ~4 dupes), `historical_50k`,
`febrl3`/`febrl4a`/`febrl4b`, and `transactions_origin`/`_destination`.
The `fake_1000_labels` file provides 3,176 pairwise clerical labels for
evaluation.

### What we added

**Real splink data bundled as `.rda` files** (via `usethis::use_data()`):

1. **`fake_1000`** — The actual splink demo dataset (1,000 rows, 181
   clusters).
   Columns: `unique_id` (0-indexed), `first_name`, `surname`, `dob`,
   `city`, `email`, `cluster`.
   Contains realistic NAs (100 missing `first_name`, 77 missing
   `surname`, 109 missing `city`, 112 missing `email`).
   Source: `../splink/tests/datasets/fake_1000_from_splink_demos.csv`.

2. **`fake_1000_labels`** — 3,176 pairwise clerical labels with columns
   `unique_id_l`, `source_dataset_l`, `unique_id_r`,
   `source_dataset_r`, `clerical_match_score` (1 = match, 0 = non-match).
   Downloaded from the splink\_datasets repository on GitHub.

3. **`febrl4a`** — 5,000 original records from the FEBRL benchmark
   (Christen and Churches, 2004).
   Columns: `rec_id`, `given_name`, `surname`, `street_number`,
   `address_1`, `address_2`, `suburb`, `postcode`, `state`,
   `date_of_birth` (YYYYMMDD integer), `soc_sec_id`.

4. **`febrl4b`** — 5,000 duplicate records, one per original in
   `febrl4a`, corrupted with typos, missing values, and transpositions.
   Same columns as `febrl4a`.
   Together, `febrl4a`/`febrl4b` provide a classic cross-table record
   linkage benchmark.

**`il_demo()` convenience loader** now returns the bundled `.rda` data
for `fake_1000`, `fake_1000_labels`, `febrl4a`, `febrl4b`, and retains
the small hardcoded `fake_20` (20 rows, no randomness).

**`R/data.R`** provides full roxygen documentation with explicit
attribution to splink and the FEBRL project.

### Design decisions

1. **Real data over synthetic.**
   The user explicitly required including actual splink datasets, not
   procedurally generated alternatives.
   This ensures comparability with splink examples and tutorials.

2. **No `set.seed()` in package code.**
   All randomness was removed from `R/il_demo.R`.
   `fake_20` is entirely hardcoded; all other datasets are `.rda` files.
   `set.seed()` may only be used in vignettes and the README.

3. **CSV cleaning: empty strings → NA.**
   Python pandas reads empty CSV cells as NaN; R's `read.csv` reads
   them as `""`.
   We convert to NA to match R conventions and splink behaviour.

4. **FEBRL for linking, fake_1000 for deduplication.**
   Two distinct scenarios are covered: deduplication (with ground-truth
   `cluster` column) and cross-table linking (with ground-truth
   `rec_id`).

## New autoplot methods

### Problem

Splink has dedicated chart functions for every diagnostic output
(`m_u_parameters_chart`, `roc_chart`, `precision_recall_chart`,
`accuracy_chart`, `unlinkables_chart`, `completeness_chart`).
irelink returned tidy tibbles from all evaluation and profiling
functions, but provided no built-in plots.
Users had to manually write ggplot2 code for every chart.

### What we added

Seven new `autoplot()` methods, all dispatching on S3 classes that are
now prepended to evaluation output tibbles:

| Method | Class | What it draws |
|--------|-------|---------------|
| `autoplot.il_model(type = "parameters")` | `il_model` | m/u probabilities side by side, faceted by level |
| `autoplot.il_accuracy()` | `il_accuracy` | Precision, recall, F1 vs. threshold |
| `autoplot.il_roc()` | `il_roc` | ROC curve with diagonal reference |
| `autoplot.il_precision_recall()` | `il_precision_recall` | PR curve |
| `autoplot.il_unlinkables()` | `il_unlinkables` | Unlinkable proportion vs. threshold |
| `autoplot.il_completeness()` | `il_completeness` | Grouped bar chart of % non-null per column |

The existing `autoplot.il_model()` (match weights) and
`autoplot.il_compared()` (histogram / waterfall) are unchanged.

### Implementation approach

- Added `add_class(x, cls)` utility in `utils-classes.R` to prepend an
  S3 class to tibble output without breaking tibble behaviour.
- Each evaluation function pipes its result through `add_class()`.
- All autoplot methods are registered via `@exportS3Method ggplot2::autoplot`.
- No new hard dependencies; ggplot2 is still in Suggests and checked at
  runtime.

## Vignettes

Two vignettes demonstrate the full workflow with evaluation:

### `deduplication.Rmd` — Deduplication with Evaluation

Uses the real splink `fake_1000` dataset and bundled `fake_1000_labels`
for evaluation.
Walks through: data profiling → spec definition → pair counting →
model training → weight inspection → prediction → clustering →
accuracy / ROC / PR / errors / unlinkables evaluation.
Demonstrates all new autoplot methods.

### `record-linkage.Rmd` — Record Linkage Across Datasets

Uses the FEBRL 4a/4b datasets (1,000-row subsets for build speed).
Walks through: completeness comparison across tables → spec with
`link_type = "link"` → training → m/u parameter chart → prediction →
clustering → evaluation with ground truth derived from `rec_id`.

Both vignettes build in under 40 seconds combined.

## Lessons from splink tutorials

Key observations from reviewing tutorials 00–08:

1. **Use real splink data for comparability.**
   Synthetic datasets diverge from splink's demos, making it harder for
   users to cross-reference.
   Bundling the actual `fake_1000` and FEBRL data ensures examples
   produce comparable results.

2. **Ground truth is essential for meaningful examples.**
   Without it, evaluation functions are just API stubs in documentation.
   The `cluster` column and `fake_1000_labels` make evaluation
   first-class.

3. **Side-by-side m/u charts matter for model diagnostics.**
   The match-weights chart alone doesn't tell you whether high weights
   come from high m or low u.
   The new `type = "parameters"` option fills this gap.

4. **Evaluation plots should be one-liners.**
   Splink wraps every diagnostic in a chart function.
   Our `autoplot()` approach achieves the same convenience while staying
   idiomatic to R's S3 dispatch system.

5. **Linking workflows need separate treatment.**
   Deduplication and record linkage have different data shapes, blocking
   considerations, and evaluation strategies.
   Having a dedicated linking vignette (with the FEBRL benchmark)
   prevents users from having to mentally translate dedupe examples.

6. **Data quality plots are the first thing users should see.**
   Both splink tutorials and our vignettes now lead with completeness
   and profiling before any model building.

## Summary of changes

| File | Change |
|------|--------|
| `data/fake_1000.rda` | NEW — real splink fake\_1000 dataset (1,000 rows, 181 clusters) |
| `data/fake_1000_labels.rda` | NEW — 3,176 pairwise clerical labels |
| `data/febrl4a.rda` | NEW — FEBRL 4a original records (5,000 rows) |
| `data/febrl4b.rda` | NEW — FEBRL 4b duplicate records (5,000 rows) |
| `R/data.R` | NEW — roxygen documentation for all 4 datasets with splink attribution |
| `R/il_demo.R` | Rewrote to load bundled `.rda` data; removed `set.seed()` and procedural generation |
| `R/autoplot.R` | Added 6 new autoplot methods; refactored ggplot2 check into `check_ggplot2()` |
| `R/utils-classes.R` | Added `add_class()` utility |
| `R/il_accuracy.R` | Output gets `il_accuracy` class |
| `R/il_roc.R` | Output gets `il_roc` class |
| `R/il_precision_recall.R` | Output gets `il_precision_recall` class |
| `R/il_unlinkables.R` | Output gets `il_unlinkables` class |
| `R/il_completeness.R` | Output gets `il_completeness` class |
| `_pkgdown.yml` | Added Datasets section; autoplot methods in Evaluation and Data Profiling |
| `tests/testthat/test-il_demo.R` | Updated for real data (181 clusters, FEBRL tests, removed patients) |
| `vignettes/deduplication.Rmd` | Updated to use bundled labels instead of hand-crafted pairs |
| `vignettes/record-linkage.Rmd` | Rewritten for FEBRL 4a/4b linking scenario |
| `README.Rmd` | Updated linking example to use FEBRL data |

devtools::check(): **0 errors, 0 warnings, 0 notes** (3m 58s).
