# 22 — Next Steps

> Gap analysis comparing the implementation plans (refs 01–21) and stage
> notes against the current codebase.
> Organized by priority into actionable work items.

---

## What Is Done

The core pipeline is complete and tested:

```
il_spec → il_model → train (u, EM, prior) → predict → cluster → evaluate
```

All 10 implementation sprints from `08-sprints.md` are finished.
Stages 1–8 from `inst/notes/goals.md` are documented in stage notes.
Feature parity with splink tutorials 00–08 was audited in
`18-feature-parity.md` and all actionable gaps were closed.
SQL-first gamma computation (ref 16), SQL push-down (ref 17), SQL
clustering (ref 21), and lazy connection support (ref 20) are all
implemented.
The package has 460+ tests, four bundled real-world datasets, four
vignettes, 10 autoplot methods, and a pkgdown site skeleton.

---

## 1 Multi-Level Gamma Support

**Source:** `18-feature-parity.md` §Design Differences;
`04-irelink-core-interface.md`

**Current state:** irelink collapses multi-level comparisons to binary
(match/non-match) for EM and scoring.
Comparison level functions like `cl_jaro_winkler(0.9, 0.7)` define
thresholds that map to gamma levels 0, 1, 2, but EM estimates only two
parameters (m and u) per comparison rather than per gamma level.

**What splink does:** splink maintains per-level m/u parameters
(e.g., `m_probability[gamma=2]`, `m_probability[gamma=1]`,
`m_probability[gamma=0]`) and sums the corresponding log-likelihood
ratios.
This gives finer-grained discriminative power, particularly for
comparisons with meaningful intermediate levels (e.g., partial name
match vs. exact name match).

**Why it matters:** Multi-level gammas are the single largest
statistical improvement opportunity.
They affect accuracy on every linkage task where fuzzy comparisons
are used, which is most tasks.

**What to do:**

- Extend the EM engine (`utils-em.R`) to track per-level m/u vectors
  instead of binary scalars.
- Update `predict.il_model()` to sum per-level contributions.
- Update `il_weights()`, `il_parameters()`, and `il_waterfall()` to
  report per-level values.
- Update autoplot methods that display parameter data.
- Ensure backwards compatibility: binary comparisons (`cl_exact()`)
  should behave identically.

**Priority:** High.
This is the most impactful improvement to linkage quality.

---

## 2 Lazy Prediction Pipeline

**Source:** `21-clusters.md` Phase 5; `17-shove-into-sql.md`

**Current state:** `predict()` materialises the full scored-pairs table
into R memory.
For large datasets with loose blocking, this can be tens of millions
of rows.
The SQL clustering pipeline (ref 21) proved that connected components,
graph metrics, and best-link filtering can all run in-database.

**What to do:**

- Add a `lazy` or `collect` argument to `predict()` that returns a
  `tbl_lazy` reference to the scored-pairs table in the database instead
  of a collected tibble.
- Update `il_cluster()` to consume the lazy reference directly,
  skipping the edge upload step when pairs are already in-database.
- Keep the current `collect = TRUE` default for backwards
  compatibility.
- Update `il_waterfall()`, `autoplot.il_compared()`, and
  `il_graph_metrics()` to `collect()` lazily when needed.

**Priority:** High for large-scale use.
This is the single largest memory and performance improvement
remaining.

---

## 3 CRAN Readiness

**Source:** General R packaging best practices; `inst/notes/goals.md`

**Current state:** Version 0.0.0.9000.
The package passes `devtools::check()` cleanly but has not been
evaluated against CRAN submission standards.

**What to do:**

- **Vignette guards:** Add `eval = requireNamespace("duckdb",
  quietly = TRUE)` (or a package-level knitr hook) to all vignette
  chunks.
  Vignettes that depend on Suggests packages must degrade gracefully
  when those packages are absent.
- **`\value` tags:** Verify every exported function's roxygen has a
  `@return` tag (CRAN requires this).
- **Run `R CMD check --as-cran`** and resolve any NOTEs.
- **Version bump** to 0.1.0 when ready for a first public release.
- **`cran-comments.md`:** Draft the CRAN submission notes.
- **`rhub::check_for_cran()`** or equivalent: test across platforms.

**Priority:** High when targeting a public release.

---

## 4 Blocking Optimisation Tools

**Source:** `07-features-for-later.md` §2; `03-splink-functions.md`

**Current state:** `il_count_pairs()` and `il_largest_blocks()` exist.
No higher-level optimisation tools.

**What to do:**

- **`il_suggest_blocking()`** — heuristic that enumerates single-column
  and two-column blocking rules, scores them by pair count vs. field
  coverage, and returns a ranked table.
  Splink's `suggest_blocking_rules()` is the reference.
- **`il_find_blocking_below()`** — recursive search for column
  combinations that keep pair counts below a user-specified ceiling.
  Useful for tuning blocking on large data.
- **`block_from_labels()`** — derive blocking rules from a labelled
  pairs table.
  Useful for supervised workflows.

**Priority:** Medium.
Valuable for users working with large or unfamiliar datasets.

---

## 5 Column Transformers

**Source:** `07-features-for-later.md` §1; `18-feature-parity.md`

**Current state:** Column pre-processing is expected to happen upstream
with `dplyr::mutate()` or dbplyr.
No in-spec transform mechanism exists.

**What to do:**

- Add a `transform` argument to `il_compare()`:
  ```r
  il_compare(name, cl_jaro_winkler(0.9), transform = tolower)
  ```
- The transform function would be applied to both left and right
  columns before comparison, translated to SQL via dbplyr when
  possible.
- Common transforms (tolower, trimws, substr) should have first-class
  SQL translations for DuckDB and PostgreSQL.

**Priority:** Medium.
Users currently must pre-process data before passing it to
`il_model()`, which is less ergonomic than in-spec transforms.

---

## 6 Evaluation Convenience

**Source:** `07-features-for-later.md` §4; `18-feature-parity.md`

### 6a Label-column evaluation wrappers

**Current state:** `il_accuracy()`, `il_roc()`, `il_precision_recall()`,
and `il_errors()` all require pairwise labels as a data frame with
`unique_id_l`, `unique_id_r`, `is_match`.
Users must manually construct these from a ground-truth column (as
demonstrated in the vignettes).

**What to do:**

- Add a `labels_col` argument (or a separate family of functions) that
  accepts a column name (like `cluster` in `fake_1000`) and
  automatically derives pairwise labels.
- This is a thin wrapper over the existing functions.

### 6b Retain original field values in predictions

**Current state:** `predict()` returns gamma columns and match
weights, but not the original field values (e.g., `first_name_l`,
`first_name_r`).
Users must join predictions back to the original data using
`unique_id_l` / `unique_id_r`.

**What to do:**

- Add a `include_fields = FALSE` argument to `predict()` that
  optionally JOINs the original field values into the output.
- This is useful for inspection and debugging but increases output
  size, so it should default to off.

**Priority:** Low.
Convenience wrappers over existing functionality.

---

## 7 EM Flexibility

**Source:** `18-feature-parity.md` §Training

**Current state:** `il_estimate_em()` always fixes u (from
`il_estimate_u()`) and freely updates m.
There is no way to fix m and update u, or to update both.

**What to do:**

- Add `fix_u = TRUE` and `fix_m = FALSE` arguments to
  `il_estimate_em()` that control which parameter sets are held
  constant during EM iterations.
- The defaults should match current behaviour (fix u, update m).

**Priority:** Low.
The current design matches splink's recommended workflow.
Advanced users who need full control can request this.

---

## 8 Documentation and Website

**Source:** `_pkgdown.yml`; vignettes; `inst/notes/goals.md`

**Current state:** pkgdown has a reference section but no articles
section.
Four vignettes exist.
README has a working example.

**What to do:**

- **pkgdown articles section:** Add an `articles:` key to
  `_pkgdown.yml` that organises vignettes into groups
  (e.g., "Getting Started", "Workflows", "Reference").
- **Advanced vignette:** Consider a vignette on production workflows
  (save/load/attach, warm-start retraining, database-native inputs).
- **Performance vignette:** A vignette or article showing benchmark
  comparisons and backend selection guidance.
- **Function lifecycle:** Add `lifecycle` badges to experimental or
  maturing functions using the `lifecycle` package.

**Priority:** Medium for discoverability and user experience.

---

## 9 Infrastructure

**Source:** General best practices

**Current state:** No CI/CD configuration detected.

**What to do:**

- **GitHub Actions:** Add `R-CMD-check.yaml` via
  `usethis::use_github_action("check-standard")`.
  Run on ubuntu, macOS, and Windows with multiple R versions.
- **Code coverage:** Add `usethis::use_github_action("test-coverage")`
  and a Codecov or Coveralls badge.
- **pkgdown deployment:** Add
  `usethis::use_github_action("pkgdown")` to auto-build the site on
  push to main.
- **Pre-commit or styler CI:** Enforce consistent code style.

**Priority:** Medium.
Essential before accepting external contributions.

---

## 10 Future Extensions

These are lower-priority items that were explicitly deferred in
`07-features-for-later.md` or excluded in `18-feature-parity.md`.
They are recorded here for completeness.

### 10a Interactive dashboards (§6 of ref 07)

A companion package (e.g., `irelink.shiny`) could provide:

- Comparison viewer: browse individual record pairs with gamma
  breakdowns.
- Cluster studio: explore clusters with drill-down into member records.
- Labelling tool: interactive clerical review for active learning.

### 10b Phonetic transforms (§7 of ref 07)

Soundex, Metaphone, and Double Metaphone are available in the `phonics`
R package.
A `cl_phonetic()` comparison level could wrap these for in-spec use.

### 10c Niche comparison levels (§10 of ref 07)

- `cl_literal()` — match against a hard-coded value.
- `cl_array_subset()` — one array is a subset of another.
- `cl_pairwise_string_distance()` — best pairwise distance between
  array elements.

All of these can be expressed today via `cl_custom()`.

### 10d Distributed backends

Spark or other distributed SQL engines could be supported through DBI
if the SQL dialect differences are handled.
Salting (`SaltedBlockingRule`) and exploding (`ExplodingBlockingRule`)
from splink would be prerequisites.

### 10e Column expression profiling

`il_profile()` currently accepts column names.
Supporting arbitrary SQL expressions (e.g.,
`"city || left(first_name, 1)"`) would match splink's
`profile_columns(column_expressions=...)`.

---

## Priority Summary

| Priority | Item | Impact |
|----------|------|--------|
| **High** | Multi-level gammas (§1) | Linkage accuracy |
| **High** | Lazy prediction pipeline (§2) | Memory and speed at scale |
| **High** | CRAN readiness (§3) | Public release |
| **Medium** | Blocking optimisation tools (§4) | Large-dataset usability |
| **Medium** | Column transformers (§5) | Ergonomics |
| **Medium** | Documentation and website (§8) | Discoverability |
| **Medium** | CI/CD infrastructure (§9) | Reliability |
| **Low** | Evaluation convenience (§6) | Ergonomics |
| **Low** | EM flexibility (§7) | Advanced use |
| **Low** | Future extensions (§10) | Completeness |

---

## Implementation Log

### §1 Multi-Level Gamma Support — Implemented

The EM engine, scoring, and all downstream consumers now operate on
per-level m/u parameters instead of binary match/non-match scalars.

**Parameter storage:**
`model$params$comparisons` changed from two rows per comparison
(`level = "match"` / `"non_match"`) to N rows per comparison
(`gamma_level = 0, 1, …, K`), where K depends on the comparison method.
Binary comparisons (`cl_exact()`, single-threshold fuzzy) still produce
exactly 2 levels; multi-threshold comparisons
(e.g., `cl_jaro_winkler(0.9, 0.7)`) produce 3; composite comparisons
(`cl_levels(...)`) produce `count(non-null, non-else sublevels) + 1`.

**New helper:** `n_gamma_levels(comp_method)` in `utils-classes.R`
returns the level count for any comparison method.

**Files changed (15):**

| File | Change |
|------|--------|
| `R/utils-classes.R` | Added `n_gamma_levels()` |
| `R/utils-sql.R` | Rewrote `sql_gamma_case()` for multi-level CASE; added `sql_sublevel_condition()` |
| `R/utils-em.R` | `compute_gamma()` returns integer 0..K instead of binary 0/1 |
| `R/utils-scoring.R` | `extract_mu_vectors()` returns `m_levels`/`u_levels` lists; `score_gamma_matrix()` does per-level weight lookup; added `migrate_params_to_gamma_level()` |
| `R/il_estimate_u.R` | Per-level u frequency counting |
| `R/il_estimate_em.R` | Multi-level E-step and M-step |
| `R/il_estimate_m_from_labels.R` | Per-level m frequencies |
| `R/il_estimate_m_from_column.R` | Per-level m frequencies |
| `R/utils-tf.R` | TF applies at highest gamma level; references `mu$u_levels` |
| `R/il_weights.R` | `level` column → `gamma_level` |
| `R/il_parameters.R` | Legacy migration support |
| `R/il_waterfall.R` | Updated `per_comparison_contribution()` call |
| `R/il_training_history.R` | `level` → `gamma_level`; legacy migration |
| `R/autoplot.R` | `autoplot.il_model()` and `autoplot.il_training_history()` updated |
| `R/il_save.R` | `il_load()` migrates legacy param format |

**Backwards compatibility:** A `migrate_params_to_gamma_level()` helper
converts the old `level` column to the new `gamma_level` format.  It is
called automatically in every function that reads model parameters,
including `il_load()`, so saved models from before this change still
work.

**Test impact:** All 506 existing tests pass.  Two test assertions were
updated (`test-il_weights.R`, `test-term-frequency.R`) and one snapshot
was regenerated (`test-stage6-plan.R`).

---

### §2 Lazy Prediction Pipeline — Implemented

`predict()` gains a `collect` argument (default `TRUE`).  When
`collect = FALSE`, the entire scoring pipeline — gamma computation,
per-level weight lookup, TF adjustment, match-probability transform,
and threshold filter — is pushed into a single SQL query.  The scored
pairs stay in a database table (`__il_predicted`) and a lightweight
`il_compared_lazy` reference is returned instead of a multi-million-row
tibble.

`il_cluster()` detects the lazy reference and creates the
connected-components edge table directly from `__il_predicted`, avoiding
the round-trip of collecting to R and re-uploading.

**New SQL helpers (in `utils-sql.R`):**

| Helper | Purpose |
|--------|---------|
| `sql_weight_case()` | CASE expression for one comparison's log2(m/u) |
| `sql_tf_adj_expr()` | CASE expression for TF adjustment at highest gamma level |
| `build_scored_query()` | Full query: gammas → weights → probability → threshold |

**New class: `il_compared_lazy`** (in `utils-classes.R`):
A list-based S3 object with `$con`, `$predicted_tbl`, `$model`,
`$threshold`, `$n_pairs`.  Has `print()` and `format()` methods.
`ensure_collected()` is an internal helper that transparently
materialises a lazy reference when downstream functions need the actual
data.

**Files changed (7):**

| File | Change |
|------|--------|
| `R/utils-sql.R` | Added `sql_weight_case()`, `sql_tf_adj_expr()`, `build_scored_query()` |
| `R/utils-classes.R` | Added `new_il_compared_lazy()`, `print`, `format`, `collect_il_compared_lazy()`, `ensure_collected()` |
| `R/predict.R` | Added `collect` parameter; new `predict_lazy()` helper |
| `R/il_cluster.R` | Added lazy detection + `cluster_lazy()` SQL-direct path |
| `R/il_waterfall.R` | Auto-collect via `ensure_collected()` |
| `R/il_graph_metrics.R` | Auto-collect via `ensure_collected()` |
| `R/autoplot.R` | Added `autoplot.il_compared_lazy()` delegate |

**Numerical fidelity:** SQL-path match weights match R-path weights to
within ~1e-14 (double-precision rounding).  Verified with and without
term-frequency adjustments.

**Workflow example:**
```r
pairs <- predict(model, threshold = 0.5, collect = FALSE)
# <il_compared_lazy> 1,234,567 pairs in table __il_predicted
clusters <- il_cluster(pairs)   # no R round-trip
```

**Test impact:** All 506 tests continue to pass (the default
`collect = TRUE` path is unchanged).
