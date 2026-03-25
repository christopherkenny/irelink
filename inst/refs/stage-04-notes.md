# Stage 4 — R Code Implementation: Summary

Stage 4 implemented every function in irelink across 10 sprints,
progressing from foundational S3 classes to a feature-complete
probabilistic record linkage package. Every sprint was gated by
pre-written tests from Stage 3. The final test suite stands at
**334 tests passing, 0 failures, 0 skips**.

## Reference documents

| Document | Contents |
|----------|----------|
| [`11-writing-r.md`](11-writing-r.md) | Sprint-by-sprint implementation log with per-sprint files, fixes, and test counts |
| [`08-sprints.md`](08-sprints.md) | Sprint definitions and dependency ordering |
| [`09-implementation-plan.md`](09-implementation-plan.md) | Detailed implementation plan (§4a–4j) |
| [`04-irelink-core-interface.md`](04-irelink-core-interface.md) | Interface design that guided API shape |

## Implementation trajectory

| Sprint | Focus | Exports | Milestone | Tests |
|:------:|-------|:-------:|-----------|:-----:|
| 1 | S3 classes, `il_spec()`, unit helpers | 14 | Data structures | 38 |
| 2 | All `cl_*()` comparison helpers | 24 | Comparison definitions | 123 |
| 3 | `il_compare()`, `il_block_on()` | 3 | Full specs | 158 |
| 4 | `il_demo()`, `il_string_similarity()` | 2 | Test data | 187 |
| 5 | SQL engine, exploration verbs | 3 | Database queries | 217 |
| 6 | `il_model()`, `il_cleanup()` | 5 | Model objects | 232 |
| 7 | EM training, model inspection | 8 | Statistical core | 259 |
| 8 | `predict()`, deterministic link, waterfall | 5 | **MVP** | 279 |
| 9 | `il_cluster()`, `il_graph_metrics()` | 2 | Entity clusters | 291 |
| 10 | Evaluation, autoplot, save/load | 9 | **Feature-complete** | 334 |

See: `11-writing-r.md` for per-sprint details.

## Architecture decisions confirmed

These decisions from Stage 2 were validated during implementation:

| Decision | Outcome |
|----------|---------|
| S3 over R6 | Functional copy-on-modify works cleanly with `|>` pipes |
| `il_spec` → `il_model` → `il_compared` type system | Clean separation of concerns; each class carries what it needs |
| `cl_*` return S3 objects, not SQL | Defers SQL generation to scoring time; keeps spec portable |
| RSQLite as primary test backend | Fast, no hangs; DuckDB deferred to Stage 6 |
| Gamma computation in R (not SQL) | RSQLite lacks string distance functions; R-side `stringdist` is sufficient |
| `il_compared` inherits from `tbl_df` | dplyr verbs work automatically — tidyverse integration "for free" |

## Key technical designs

### EM algorithm (`R/il_estimate_em.R`, `R/utils-em.R`)

Binary gamma per comparison (match = 1, non-match = 0). E-step in log
space for numerical stability. M-step with Laplace smoothing (0.5
pseudocount) and clamping to [0.01, 0.99] to prevent degenerate models.
U values are frozen from `il_estimate_u()` and not updated during EM.
Multiple EM passes with different blocking rules refine rather than
reset parameters.

See: `11-writing-r.md`, Sprint 7 and "Key design: EM M-step clamping".

### Scoring (`R/predict.R`)

Match weight is a log2 Bayes factor summed across comparisons. Match
probability converts via logistic transform including the prior.
`il_waterfall()` decomposes the weight into per-comparison contributions
that sum exactly to the total.

See: `11-writing-r.md`, Sprint 8.

### Clustering (`R/il_cluster.R`)

Union-find with path compression and rank for connected components.
Best-link method uses mutual best links — an edge is kept only if both
endpoints select it as their best. Threshold filtering collects all
unique IDs before filtering edges, so isolated nodes get their own
cluster.

See: `11-writing-r.md`, Sprint 9.

### Serialization (`R/il_save.R`)

JSON via jsonlite with `digits = NA` for full floating-point precision.
S3 classes are stripped with `unclass()` before writing and restored on
load. The loaded model has `con = NULL` — a fresh database connection
must be supplied for prediction.

See: `11-writing-r.md`, Sprint 10.

## Notable bugs fixed during implementation

| Bug | Sprint | Root cause | Fix |
|-----|:------:|------------|-----|
| `cli::cli_*()` in print methods fails `expect_output()` | 1 | cli writes to stderr | Use `cat()` instead |
| EM produces m ≈ 1.0 on highly similar pairs | 7–8 | No upper bound on m estimate | Clamp to [0.01, 0.99] with Laplace smoothing |
| `\x00` null char in pair dedup key | 8 | R source parser rejects null bytes | Use `"||"` separator |
| `il_find_matches` returns 0 matches | 8 | Iterates over all data columns, not comparison columns | Only iterate comparison columns |
| `rlang::enquo(x)[[2]]` deprecation | 7 | Old rlang extraction pattern | Use `rlang::as_name(rlang::enquo(x))` |
| `jsonlite` can't serialize S3 classes | 10 | `as.list()` retains class attribute | Use `unclass()` before serialization |
| Test data with all-unique blocking column | 10 | Blocking produces 0 pairs, EM errors | Fixed test data to have duplicates |
| `il_weights()` column name mismatch | 10 | Sprint 7 test used `match_weight`, sprint 10 used `weight` | Unified to `weight` |

## Dependency evolution

| Sprint | Added to Imports | Added to Suggests |
|:------:|:----------------:|:-----------------:|
| 1 | cli, rlang, tibble | testthat, withr |
| 4 | stringdist | — |
| 5 | DBI | RSQLite |
| 9 | — | dplyr, igraph |
| 10 | — | ggplot2, jsonlite |

**Final Imports**: cli, DBI, rlang, stringdist, tibble
**Final Suggests**: dplyr, ggplot2, igraph, jsonlite, RSQLite, testthat (≥ 3.0.0), withr

## Package state at end of Stage 4

```
47 R source files (all implemented)
71 exported functions + 6 internal class utilities
27 test files, 334 tests — all passing
70 .Rd documentation files
NAMESPACE with 71 exports + 6 S3 method registrations

Full pipeline works:
  il_spec() |> il_compare() |> il_block_on() |>
  il_model(data, spec = _, con = con) |>
  il_estimate_u() |> il_estimate_em() |>
  predict(threshold = 0.5) |>
  il_cluster()
```

## Open items for Stage 5+

Per `inst/notes/goals.md`, the remaining stages are:

- **Stage 5 (Simplification):** Deduplicate shared logic, enforce
  consistent style, remove dead code paths.
- **Stage 6 (Test review):** Add R-specific type safety tests, snapshot
  tests, backend compatibility matrix, tidyverse integration tests
  beyond the 14 already included.
- **Stage 7 (Performance):** Benchmark against splink, profile hot
  paths, check for non-vectorized loops that should be vectorized.

Additionally, features deferred from Stage 4 (documented in
[`07-features-for-later.md`](07-features-for-later.md)) include term
frequency adjustments, column transformers, salted/exploding blocking,
multi-backend support (PostgreSQL, Spark), interactive dashboards, and
custom SQL comparison functions.
