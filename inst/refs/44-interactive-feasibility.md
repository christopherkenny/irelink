# Interactive Graph Feasibility: Quarto + OJS

This note reassesses the earlier decision to exclude interactive graphs from
`irelink`, specifically for a very lightweight implementation using Quarto and
Observable JS (OJS). The goal is not to reproduce Splink's front-end product.
It is to decide whether `irelink` can offer a useful optional interactive path
without adding runtime charting dependencies or taking on dashboard maintenance.

## Short Answer

Feasible, but only if the scope is deliberately narrow.

The promising route is a Quarto document generator that writes a self-contained
`.qmd` from existing `irelink` diagnostic data. The `.qmd` can use OJS cells for
tooltips, sliders, threshold exploration, and row selection. This would require
`quarto` as a `Suggests` dependency only, and only for users who call the
interactive export function.

Do not port Splink's dashboards wholesale. Splink has two different
visualisation layers:

1. simple Vega-Lite chart specs with records injected; and
2. standalone dashboards built from templates, bundled JavaScript, custom CSS,
   and Splink-specific visual utilities.

The first category is feasible to approximate. The second category is a product
surface, not just a chart surface.

## What Splink Actually Does

Splink's chart core lives in `../splink/splink/internals/charts.py`. Most chart
functions load a JSON Vega-Lite spec from
`../splink/splink/internals/files/chart_defs/`, inject `data.values`, and return
either an Altair chart or a dictionary:

- `match_weights_chart()`
- `m_u_parameters_chart()`
- `match_weights_histogram()`
- `parameter_estimate_comparisons()`
- `waterfall_chart()`
- `roc_chart()`
- `precision_recall_chart()`
- `accuracy_chart()`
- `unlinkables_chart()`
- `completeness_chart()`
- comparator and phonetic charts

Splink's waterfall is a good example. `charts.py::waterfall_chart()` calls
`records_to_waterfall_data()` from
`../splink/splink/internals/waterfall_chart.py`, injects those records into
`match_weights_waterfall.json`, and exposes a Vega-Lite slider bound to
`record_number`.

Splink's heavier dashboards are different:

- `comparison_viewer_dashboard()` in
  `../splink/splink/internals/linker_components/visualisations.py`
  builds comparison-vector distribution tables, samples example rows, and calls
  `render_splink_comparison_viewer_html()`.
- `cluster_studio_dashboard()` samples clusters, gathers node and edge records,
  and calls `render_splink_cluster_studio_html()`.
- The renderers in `../splink/splink/internals/splink_comparison_viewer.py` and
  `../splink/splink/internals/cluster_studio.py` use Jinja templates and bundle
  Vega, Vega-Lite, Vega Embed, Observable stdlib, `splink_vis_utils.js`, and
  custom CSS.

That split matters. A small optional Quarto/OJS implementation can imitate the
single-chart behavior, but full dashboard parity would mean owning custom
JavaScript application code.

## Current `irelink` Starting Point

`irelink` is in a good position for a lightweight version because the data
surfaces already exist:

- `il_weights(model)` for match weights;
- `il_parameters(model)` for m/u parameters;
- `il_training_history(model)` for EM history;
- `il_waterfall(pairs, which)` for pair decomposition;
- `il_unlinkables(model)` for unlinkability curves;
- `il_accuracy()`, `il_roc()`, and `il_precision_recall()` for threshold
  diagnostics;
- `il_completeness()`, `il_profile()`, `il_count_pairs()`, and
  `il_comparison_vectors()` for exploratory diagnostics;
- `il_tf_chart()` and comparator charts for term-frequency and string-similarity
  diagnostics.

The existing public plotting contract is static `ggplot2`. An interactive layer
should preserve that: static plots remain the core package API; interactive
output is an export/report option.

## Why Quarto + OJS Is Plausible

Quarto has native support for Observable JS in `{ojs}` cells, including a
reactive runtime for interactive exploration:
<https://quarto.org/docs/interactive/ojs/>.

Quarto's OJS documentation also describes passing R/Python data into OJS and
using `transpose()` when column-oriented data needs to become row-oriented data
for JavaScript plotting:
<https://quarto.org/docs/interactive/ojs/data-sources.html>.

That fits `irelink` well:

- R computes all model, prediction, and diagnostic data.
- The generated Quarto file embeds small diagnostic datasets as JSON.
- OJS handles client-side filtering, threshold sliders, row selectors, tooltips,
  and compact interactive charts.
- No `htmlwidgets`, `plotly`, `reactable`, `DT`, Shiny, or V8 dependency is
  required in the package.

The implementation can shell out to the Quarto CLI only when explicitly asked
to render. If Quarto is not installed, the package can still write the `.qmd`
and tell the user how to render it.

## Recommended Scope

Implement one optional report/export function, not a family of interactive
objects:

```r
il_interactive_report <- function(
  model,
  pairs = NULL,
  path = "irelink-report.qmd",
  render = FALSE,
  max_pairs = 1000,
  include_sensitive = FALSE,
  overwrite = FALSE
)
```

The function would:

1. collect or derive bounded diagnostic tibbles;
2. write a Quarto `.qmd` using an installed template under `inst/quarto/`;
3. optionally call `quarto::quarto_render(path)` when `render = TRUE` and
   `quarto` is installed;
4. avoid running prediction implicitly unless the user supplies `pairs`, or keep
   any implicit prediction capped and explicit.

Suggested first report sections:

- match weight chart from `il_weights(model)`;
- m/u parameter chart from `il_parameters(model)`;
- prediction histogram when `pairs` is supplied;
- waterfall inspector for a sampled set of pairs;
- unlinkables curve from `il_unlinkables(model)`;
- accuracy/ROC/precision-recall when labelled diagnostics are supplied later;
- comparison-vector distribution if `il_comparison_vectors(model)` is cheap
  enough for the model.

The waterfall inspector is the clearest first interactive win: Splink's
waterfall chart uses a `record_number` slider, and `irelink` can do the same by
precomputing waterfall rows for a capped number of pairs.

## Keep Out of Scope

Do not implement these in the core package:

- Splink's full `comparison_viewer_dashboard()`;
- Splink's full `cluster_studio_dashboard()`;
- a labelling tool;
- persistent custom JavaScript application state;
- server-side interactivity;
- interactive objects returned from `autoplot()`;
- new required charting packages.

Those would pull `irelink` toward a dashboard product. If they become important,
they belong in a companion package or a separate Quarto template collection.

## Dependency Position

`DESCRIPTION` currently imports `ggplot2` and suggests `jsonlite`, `knitr`, and
`rmarkdown`. A lightweight implementation would add:

```text
Suggests:
    quarto
```

`jsonlite` is already suggested and can be used for writing embedded JSON. The
package should not add `htmlwidgets`, `plotly`, `DT`, `reactable`, `crosstalk`,
`shiny`, or a JavaScript runtime package.

Because `quarto` is an R wrapper around the Quarto CLI, rendering should be
optional. Writing the `.qmd` should work without Quarto installed.

## Data and Privacy Constraints

Interactive HTML can easily embed record-level data. That is a bigger concern
for record linkage than for ordinary charts.

Recommended defaults:

- `include_sensitive = FALSE`;
- cap pair records with `max_pairs`;
- include IDs, gamma columns, weights, and probabilities by default;
- omit raw left/right field values unless the user opts in;
- make the generated report title or preamble state that rendered HTML is a
  data artifact and may contain embedded linkage records.

This differs from Splink's waterfall option
`remove_sensitive_data = FALSE`; `irelink` should default the other way.

## Implementation Sketch

Add an internal writer layer rather than hard-coding a huge string in R:

- `inst/quarto/interactive-report.qmd`
- `R/il_interactive_report.R`
- possibly `R/utils-interactive.R`

The R function can write data files beside the report:

```text
irelink-report.qmd
irelink-report-data/
  weights.json
  parameters.json
  pairs.json
  waterfall.json
  unlinkables.json
```

This is preferable to embedding large JSON blobs directly into the `.qmd`. It
also lets OJS load data with `FileAttachment()` in rendered documents. For
small reports, embedding inline JSON is acceptable, but sidecar files are easier
to inspect and test.

Testing should be modest:

- template file exists;
- `il_interactive_report(..., render = FALSE)` writes the `.qmd` and data files;
- sensitive columns are absent by default;
- pair sampling respects `max_pairs`;
- rendering tests are skipped unless both `quarto` and the Quarto CLI are
  installed.

## Feasibility by Splink Feature

| Splink feature | Lightweight `irelink` feasibility | Notes |
|---|---|---|
| `match_weights_chart()` | High | Existing `il_weights()` data is enough. |
| `m_u_parameters_chart()` | High | Existing `il_parameters()` / `il_weights()` data is enough. |
| `match_weights_histogram()` | High | Existing `predict()` output is enough. |
| `waterfall_chart(records)` | High | Best first target; use capped precomputed waterfall rows and an OJS selector. |
| `unlinkables_chart()` | High | Existing `il_unlinkables()` data is enough. |
| `accuracy_chart()`, ROC, PR | High | Existing labelled diagnostic tibbles are enough. |
| `tf_adjustment_chart()` | Medium | Existing chart function returns a ggplot, but the underlying TF data may need a helper if we want JSON rather than static image output. |
| `profile_columns()` style charts | Medium | Existing `il_profile()` is enough for simple top-N bar charts. |
| `comparison_viewer_dashboard()` | Low | Requires sampled examples, comparison-vector grouping UI, custom JS, and careful privacy handling. |
| `cluster_studio_dashboard()` | Low | Requires graph UI and cluster sampling; better as a separate project. |
| labelling tool | Low | Workflow/product feature, not a chart. |

## Recommendation

Proceed only with a narrow prototype:

1. Add `quarto` to `Suggests`.
2. Add `il_interactive_report()` that writes a Quarto report and optionally
   renders it.
3. Start with match weights, parameters, prediction histogram, waterfall
   inspector, and unlinkables.
4. Keep `autoplot()` static and unchanged.
5. Document this as an optional exploratory report, not Splink dashboard parity.

This gives users a genuinely useful interactive artifact while preserving the
package's current strengths: tidy data, static `ggplot2` charts, DBI-first
execution, and a small dependency footprint.

