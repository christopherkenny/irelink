# 27 — Documentation and Vignette Polish

> A targeted pass improving example quality, NEWS.md tone, and vignette
> coverage. Covers all changes made after the gap audit in
> `26-polish.md`.

---

## Changes made

### Example cleanup — `\dontrun` removal

All `\dontrun{}` blocks were removed from exported function examples.
CRAN policy allows `\dontrun` only when an example cannot run at all
(e.g., requires a live API key or a system binary). Wrapping in
`\donttest{}` is correct for examples that are valid but slow.

| Function | File | Change |
|----------|------|--------|
| `il_attach()` | `R/il_model.R` | Replaced with `\donttest` containing a complete `il_spec → il_model → il_estimate_u → il_estimate_em → il_save → il_load → il_attach` pipeline using `fake_1000` and `tempfile()` |
| `il_find_blocking_below()` | `R/il_suggest_blocking.R` | Replaced with a fully runnable example using `fake_1000` and `max_pairs = 100000` |
| `block_from_labels()` | `R/il_suggest_blocking.R` | Replaced with a fully runnable example using `fake_1000` and `fake_1000_labels` |
| `labels_from_column()` | `R/utils-evaluation.R` | Replaced with `\donttest` containing a complete training pipeline followed by the function call |

`devtools::document()` was re-run after these changes to regenerate the
four affected `.Rd` files.

---

### NEWS.md language

The initial release NEWS had several bullets written as if they
described changes to a prior version ("now accepts", "is a new", etc.).
Since this is a first release, all such language was rewritten to
describe features without implying a predecessor:

| Original phrase | Replaced with |
|-----------------|---------------|
| `cl_first_last_name()` is a **new** American-English alias | `cl_first_last_name()` is an American-English alias |
| `cl_forename_surname()` **now accepts** a `surname` argument | `cl_forename_surname()` accepts a `surname` argument |
| `cl_zip_code()` is a **new** domain comparison | `cl_zip_code()` is a domain comparison |
| ...`cl_postcode()` **now accept** `term_frequency = TRUE` | ...`cl_postcode()` accept `term_frequency = TRUE` |
| `il_profile()` **now accepts** raw SQL expressions | `il_profile()` accepts raw SQL expressions |
| `predict()` **now supports** `include_fields = TRUE` | `predict()` supports `include_fields = TRUE` |

The bullet for `predict()` also had its final sentence removed
("Previously `include_fields` was silently ignored on the lazy path.")
as this implies a regression fix in a prior version.

---

### Vignette additions to `deduplication.Rmd`

A coverage audit of all four vignettes found that several recently
implemented functions had no working vignette demonstration. Two
sections were added to `vignettes/deduplication.Rmd`.

**§1 "Choose blocking rules"** (inserted after "Explore the data",
before "Define the specification")

Calls `il_suggest_blocking(df, con = con)` and explains the output
columns (`n_distinct`, `coverage`, `score`). The prose bridges directly
to the spec below it, noting that `first_name`, `surname`, and `city`
rank among the top columns. This is the first vignette demonstration
of `il_suggest_blocking()`.

**§2 "Save and reuse the model"** (inserted after "Inspect the trained
model", before "Predict and cluster")

Shows the full persistence round-trip: `il_save(model, path)` writes
to a `tempfile()`, then `il_load()` and `il_attach()` restore the
model on a fresh connection and call `predict()`. This is the first
runnable end-to-end demonstration of `il_save()`, `il_load()`, and
`il_attach()` in any vignette. Previously these functions appeared only
as a table row in `from_splink.Rmd`.

---

## Vignette coverage audit

Full audit of all four vignettes after the additions above.

### Covered

| Feature | Vignette |
|---------|----------|
| Core pipeline (spec → model → train → predict → cluster → cleanup) | All |
| `il_completeness()` + `autoplot()` | deduplication, record-linkage |
| `il_profile()` | deduplication |
| `il_count_pairs()` | deduplication |
| `il_suggest_blocking()` | deduplication (new) |
| `il_estimate_prior()` | deduplication, record-linkage |
| `autoplot(model)` — match weights | deduplication, record-linkage |
| `autoplot(model, type = "parameters")` | deduplication, record-linkage |
| `autoplot(predictions)` — histogram | deduplication, record-linkage |
| `autoplot(predictions, which = 1)` — waterfall | deduplication |
| `il_accuracy()`, `il_roc()`, `il_precision_recall()`, `il_errors()` + plots | deduplication, record-linkage |
| `il_unlinkables()` + `autoplot()` | deduplication |
| `il_weights()` | irelink (Getting Started), record-linkage |
| `cl_name()`, `cl_dob()`, `cl_email()`, `cl_exact()`, `cl_jaro_winkler()` | deduplication, irelink |
| `term_frequency = TRUE` via `cl_exact()` | deduplication |
| Cross-table `link_type = "link"` | record-linkage |
| `il_save()`, `il_load()`, `il_attach()` | deduplication (new) |

### Remaining gaps (no runnable vignette coverage)

| Feature | Functions | Priority |
|---------|-----------|----------|
| EM convergence monitoring | `il_training_history()` + `autoplot()` | Medium |
| Pair inspection | `il_compare_records()` | Medium |
| Post-cluster analysis | `il_graph_metrics()` | Low |
| Lazy prediction | `predict(collect = FALSE)` + lazy `il_cluster()` | Medium |
| Phonetic blocking | `block_on(.where = "il_soundex(...)")` | Medium |
| Column transforms | `transform` arg in `il_compare()` | Low |
| Incremental matching | `il_find_matches()` | Medium |

---

### Serialisation: RDS replaces JSON

`il_save()` and `il_load()` were rewritten to use `saveRDS`/`readRDS`
instead of `jsonlite`. The JSON path was inherited from splink
(Python interoperability) but is wrong for an R-to-R workflow:
`jsonlite::read_json(simplifyVector = TRUE)` silently coerced nested
lists of `il_comparison_level` objects (sub-levels in `cl_name()`,
`cl_dob()`, etc.) into data frames, causing a "condition has length > 1"
error in `sql_sublevel_condition` when vignettes were built.

Changes:

| File | Change |
|------|--------|
| `R/il_save.R` | Replaced `jsonlite::write_json` / `read_json` with `saveRDS` / `readRDS`; deleted `unclass_comparison_level()` helper (JSON-only) |
| `R/utils-sql.R` | Deleted `name_to_transform()` helper (JSON-only); fixed two roxygen `[internal_fn]` links that caused `devtools::check()` warnings |
| `R/predict.R` | Fixed roxygen `[il_compared_lazy]` link |
| `DESCRIPTION` | Removed `jsonlite` from `Imports` |
| `NEWS.md` | Updated `il_save()` bullet to describe RDS format |
| `vignettes/deduplication.Rmd` | `.json` → `.rds` extension in save/load example |
| `R/il_model.R` | `.json` → `.rds` in roxygen example |
| `tests/testthat/test-il_save.R` | Rewrote "valid JSON" test as "valid RDS" test; removed `jsonlite::read_json` call |
| `tests/testthat/test-il_phonetic.R` | Removed `name_to_transform` round-trip tests (function deleted) |

---

### `@importFrom` audit

Policy: `@importFrom` should be used only for rlang's `.data` and `:=`.
All other packages should be called with `pkg::fn()` inline.

| File | Change |
|------|--------|
| `R/il_waterfall.R` | Removed `@importFrom utils head`; changed `head(cumulative, -1)` → `utils::head(cumulative, -1)` |
| `R/il_cluster.R` | Changed three bare `setNames()` calls → `stats::setNames()` |
| `R/irelink-package.R` | Removed `setNames` from `@importFrom stats predict setNames` |

---

### Example positional-argument fix

`il_model(.data, ..., spec, con)` has `...` between `.data` and `spec`,
so `spec` cannot be passed positionally. Two roxygen examples were
calling `il_model(fake_1000, spec, con = con)` — `spec` was being
captured by `...` and the named argument was never set.

| File | Change |
|------|--------|
| `R/il_model.R` | `il_model(fake_1000, spec, ...)` → `il_model(fake_1000, spec = spec, ...)` |
| `R/utils-evaluation.R` | Same fix |

---

### `vignettes/advanced.Rmd` — implemented

All seven planned sections were written and the vignette builds cleanly.
The "remaining gaps" table in the coverage audit above is now fully
closed. `_pkgdown.yml` was updated with an `articles:` section grouping
all five vignettes under a shared navbar entry.

| Section | Functions demonstrated |
|---------|----------------------|
| Training diagnostics | `il_training_history()`, `autoplot(hist)` |
| Pair inspection | `il_compare_records()`, `il_weights()`, `autoplot(pairs, which = 1)` |
| Lazy prediction | `predict(collect = FALSE)`, lazy `il_cluster()` |
| Cluster diagnostics | `il_graph_metrics()` — nodes, edges, clusters tables |
| Phonetic blocking | `il_block_on(.transform = il_soundex)`, `block_on(.transform = il_soundex)` |
| Column transforms | `il_compare(transform = tolower)` |
| Incremental matching | `il_find_matches()` |

Final `devtools::check()` result: 0 errors, 0 warnings, 0 notes.

---

## Plan: `vignettes/advanced.Rmd`

**Title:** Advanced Workflows
**Audience:** Users who have completed the Getting Started or
Deduplication vignettes.
**Data:** `fake_1000` throughout — no new datasets required.

The vignette moves from diagnostics (understanding what the model
learned) through production patterns (large data, incremental updates)
to field-matching techniques (phonetics, transforms).
After writing the vignette, add an `articles:` section to
`_pkgdown.yml` that groups all five vignettes.

---

### Section 1 — Training diagnostics

`il_training_history()` records the m/u estimates after every EM call.

```r
model <- il_estimate_em(model, block_on(surname))
model <- il_estimate_em(model, block_on(dob))
hist <- il_training_history(model)
autoplot(hist)
```

A well-converged model shows stable parameter values across the final
EM iterations. Recommend additional EM passes if parameters are still
drifting.

---

### Section 2 — Pair inspection

`il_compare_records()` scores two specific records against the spec,
returning a row-per-comparison breakdown. Primary use: debug why a
known match is scored too low.

```r
rec_a <- fake_1000[1, ]
rec_b <- fake_1000[2, ]
il_compare_records(rec_a, rec_b, spec = model$spec, con = con)
```

Explain the gamma columns and how per-comparison weights sum to the
final match weight.

---

### Section 3 — Cluster analysis

`il_graph_metrics()` summarises cluster structure after scoring.

```r
pairs <- predict(model, threshold = 0.5)
il_graph_metrics(pairs)
```

Key metrics: `n_nodes`, `n_edges`, `n_components`,
`max_component_size`. A very large maximum component often signals
over-generous thresholding or a blocking rule that creates spurious
links.

---

### Section 4 — Lazy prediction for large data

`predict(collect = FALSE)` keeps scored pairs in the database.
`il_cluster()` detects the lazy reference and runs connected components
in SQL, avoiding R-side materialisation.

```r
pairs_lazy <- predict(model, threshold = 0.5, collect = FALSE)
pairs_lazy  # <il_compared_lazy> N pairs in __il_predicted

clusters <- il_cluster(pairs_lazy)  # no R round-trip
```

Use when candidate-pair counts exceed available memory.
`autoplot()` and `il_waterfall()` auto-collect when needed, so
downstream code is unchanged.

---

### Section 5 — Phonetic blocking

Phonetic blocking catches pairs where names sound alike but are spelled
differently (e.g., "Smith" / "Smyth", "Jon" / "John"). Use
`il_soundex()` or `il_metaphone()` inside a `block_on(.where = ...)`
call:

```r
model <- il_estimate_em(
  model,
  block_on(.where = "il_soundex(l.first_name) = il_soundex(r.first_name)")
)
```

On DuckDB, `il_soundex()` and `il_metaphone()` are registered as SQL
macros so computation stays in-database. Both are also available as
standalone R functions for pre-computing phonetic columns upstream.

---

### Section 6 — Column transforms

The `transform` argument in `il_compare()` applies a function to both
columns before scoring. Known transforms (`tolower`, `toupper`,
`trimws`) are translated to SQL on DuckDB; custom R functions work on
the SQLite fallback path.

```r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7), transform = tolower) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7), transform = tolower)
```

Note serialisation behaviour: `il_save()` stores transform names as
strings and restores them on `il_load()`. Anonymous functions cannot be
restored and produce a warning on save.

---

### Section 7 — Incremental matching

`il_find_matches()` scores new records against a trained model without
retraining. Returns the same columns as `predict()` — one row per
(new record, existing record) pair above threshold.

```r
new_df <- data.frame(
  first_name = c("Jhon", "Alice"),
  surname    = c("Smith", "Jones"),
  dob        = c("1990-01-15", "1985-06-20"),
  city       = c("London", "Manchester"),
  email      = c(NA, "ajones@example.com")
)
matches <- il_find_matches(model, new_df, threshold = 0.5)
matches
```

Natural pairing with `il_load()` → `il_attach()`: load a saved model,
attach it to the current database, and call `il_find_matches()` for
each incoming batch.
