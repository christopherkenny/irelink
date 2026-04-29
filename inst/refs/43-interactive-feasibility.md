# Interactive graph feasibility: Quarto + OJS

## Background

Splink ships 19 interactive charts, two full dashboards (Cluster Studio and
Comparison Viewer), and a labelling tool. All are browser-based, rendered
from Vega-Lite JSON specs or a bundled Observable JS runtime + Vega + a
custom `splink_vis_utils` library, all inlined into self-contained HTML
files.

irelink currently covers the same analytical ground with static ggplot2
charts. The question is whether a lightweight, dependency-minimal interactive
layer is feasible using Quarto and OJS.

## How Quarto + OJS would work

Quarto supports OJS cells natively. Observable Plot (the modern successor to
D3-based plotting from the Observable team) is bundled into Quarto itself and
available without any `require()` call. This means:

- Static-ish charts (bars, lines, histograms) → Observable Plot, zero CDN
  calls, offline-capable.
- Force-directed network graphs (clusters) → D3, loaded via `require("d3")`
  in OJS, which does need internet.

The R-side pattern would be:

1. Data extraction functions (already exist: `il_waterfall()`, `il_weights()`,
   etc.) return tidy tibbles.
2. A thin wrapper serializes to JSON and calls `quarto::quarto_render()` on a
   template stored in `inst/templates/`.
3. The rendered HTML is opened with `browseURL()`.

`quarto` (the R package) would go in `Suggests`. No other new package
dependencies are needed. The Quarto CLI itself must be installed separately;
the R package is a thin wrapper around it.

## What splink's interactive charts actually do

| Chart | Key interactivity | Data consumed |
|---|---|---|
| Waterfall | Pair-selector slider; bars update live | `record_number`, `column_name`, `log2_bayes_factor`, `value_l`, `value_r` per comparison step |
| M/U history | EM-iteration slider | Parameter estimates per iteration |
| Training history | Same slider | Same |
| Match weight histogram | Hover tooltip | `match_weight` per pair |
| Cluster Studio | Cluster selector; color/size/filter controls; force graph | Nodes + edges with cluster IDs, match weights, record fields |
| Comparison Viewer | Gamma-level filter; per-pair waterfall inset | All comparison vector columns + raw field values |
| Threshold tool | Threshold drag; live precision/recall readout | Accuracy metrics at each threshold |

The cluster studio and comparison viewer embed the full Observable runtime
plus Vega/Vega-Lite (several hundred kB of bundled JS). They are not
lightweight. The simpler charts are just Vega-Lite JSON specs with data
injected.

## Feasibility by chart

### Tier 1 — straightforward (Observable Plot, offline, no new JS)

**Interactive waterfall** is the highest-value target. Users currently have
to call `il_waterfall(pairs, which = i)` separately for each pair. A slider
that re-renders the waterfall for any pair is a genuine UX leap. The data
structure from `il_waterfall()` maps directly; the OJS implementation is a
~30-line Observable Plot script. A single `.qmd` template in
`inst/templates/` plus a thin `il_waterfall_chart()` wrapper covers it.

**Match weight histogram** already exists as a static chart. Interactive
hover tooltips and a threshold-drag to mark a cutoff would add value. Low
effort.

**Training history / M/U history sliders** are nice-to-haves. The static
ggplot2 versions are already readable; the improvement is marginal.

**Accuracy / ROC / precision-recall with threshold indicator** — line charts
with a draggable vertical line is easy in Observable Plot and more useful
than the static versions.

### Tier 2 — moderate (D3 via require, needs internet)

**Cluster network graph** is not currently implemented at all (igraph is in
Suggests but unused for visualization). A force-directed graph of linked
record groups would be genuinely new functionality and a compelling feature.
OJS can `require("d3")` and the standard D3 force simulation is well
documented. The data (nodes + edges from `il_cluster()`) maps naturally.
This is the second priority after the waterfall.

### Tier 3 — not feasible without heavy work

**Comparison Viewer** requires per-cluster SQL queries in response to UI
interaction. That pattern assumes a live backend, which Quarto + OJS does
not provide. The data would have to be pre-fetched in full (could be large).

**Labelling tool** is a full CRUD interface. Out of scope.

## Concrete risks

**Quarto CLI is not the R package.** `quarto` in Suggests declares the R
wrapper, but the user must also have the Quarto CLI installed. RStudio bundles
it since 2022.4; Positron bundles it too; VS Code does not. The package
must detect the CLI at runtime and emit a clear error if absent.

**CDN dependency for D3.** Observable Plot is offline-capable, but D3 for
the cluster graph loads from the jsDelivr CDN inside the OJS cell. Offline
users can't render it. This is acceptable for an interactive-only feature
but must be documented.

**Temporary file lifecycle.** `quarto_render()` writes to a temp file;
`browseURL()` opens it. The file disappears when the R session ends. For
anything the user wants to keep, they'd pass an `output` argument.

**Template maintenance.** `.qmd` templates in `inst/templates/` are
effectively bundled source files. They'll need to be updated if Quarto's OJS
API changes, though that API is stable.

## Recommended scope

Start with these two charts:

1. `il_waterfall_chart(pairs, which = NULL, output = NULL)` — renders an
   interactive waterfall. `which = NULL` presents all pairs (slider picks
   one); `which = i` pre-selects a single pair. Opens in browser or writes
   to `output` path.

2. `il_cluster_chart(clusters, output = NULL)` — renders a force-directed
   network of linked record clusters. Nodes colored by cluster, edges weighted
   by match probability. Needs internet for D3.

Both should degrade gracefully: if Quarto is not available, print a clear
message and return the data invisibly so the user can build their own chart.

## Implementation sketch

```
inst/
  templates/
    waterfall.qmd     # OJS waterfall with pair slider
    clusters.qmd      # D3 force graph with cluster selector
R/
  il_interactive.R    # il_waterfall_chart(), il_cluster_chart()
```

The `.qmd` templates receive data via `params` (Quarto parameters). The R
wrapper writes data as JSON to a tempfile, substitutes the path into the
template, and calls `quarto::quarto_render()`.

Observable Plot's `Plot.rectY()` / `Plot.barX()` handles the waterfall
geometry well. The OJS pair-selector is a simple `Inputs.range()` bound to
a filter transform — about 10 lines.

The cluster graph needs D3's force simulation (maybe 50 lines of OJS).
Splink's cluster studio can serve as a direct reference for the data model
and interaction design.

## Conclusion

Feasible and worth doing for two charts. The waterfall pair-selector
transforms a currently awkward workflow into a first-class interactive tool.
The cluster network graph would be new functionality with no current static
equivalent. Both fit cleanly into the Quarto + OJS pattern with `quarto` in
Suggests and no other new formal dependencies.
