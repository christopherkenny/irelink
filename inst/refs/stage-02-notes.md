# Stage 2 — Planning: Summary

Stage 2 took the research and scope established in Stage 1 and produced
a complete package skeleton: every function stubbed, documented, and
organised into an implementation roadmap.

## Reference documents produced

| Document | Size | Contents |
|----------|------|----------|
| [`03-splink-functions.md`](03-splink-functions.md) | 615 lines | Complete catalog of ~233 splink functions across 17 categories |
| [`04-irelink-core-interface.md`](04-irelink-core-interface.md) | 1183 lines | Interface design: S3 types, pipe patterns, 36+ code examples, gt lessons |
| [`05-file-function-structure.md`](05-file-function-structure.md) | 226 lines | File → function map for 47 R files and 71 exports |
| [`06-function-draft-documentation.md`](06-function-draft-documentation.md) | 157 lines | Roxygen conventions and documentation audit |
| [`07-features-for-later.md`](07-features-for-later.md) | ~300 lines | Gap analysis: 13 categories of deferred features with priority |
| [`08-sprints.md`](08-sprints.md) | ~850 lines | 10 implementation sprints with dependency ordering and test targets |
| [`09-implementation-plan.md`](09-implementation-plan.md) | ~900 lines | Detailed plan for Stages 3–7 |

## What was built

### Function catalog (2a)

Every meaningful function in splink (~233 items) was cataloged by name,
kind, visibility, description, and source file. The catalog is organised
into 17 sections covering the full splink API surface: core Linker,
settings, comparisons, comparison levels, blocking, training, inference,
clustering, evaluation, visualisations, table management, misc, column
expressions, datasets, exploration, and testing utilities.

See: `03-splink-functions.md`.

### Interface design (2b)

The irelink interface was designed from scratch as a tidyverse-native
API, not a direct port of splink. Key design decisions:

| Decision | Choice | Inspiration |
|----------|--------|-------------|
| Class system | S3 (not R6) | Base R, vctrs, tibble |
| Pipe operator | `\|>` (not `+`) | gt (not ggplot2) |
| Column selection | Tidyselect | dplyr, gt |
| Prefix convention | `il_` for core, `cl_` for comparisons | gt's `tab_`, `fmt_`, `cols_` |
| Unit helpers | `days()`, `km()` tagged values | gt's `px()`, `pct()` |
| Accumulation | Multiple calls append, never overwrite | gt, ggplot2 layers |
| Return types | Tibbles everywhere possible | Tidyverse convention |
| Visualisation | Data extraction → ggplot2 | broom, forecast |

Three S3 classes form the type system:

- **`il_spec`** — declarative specification (data-free). Holds
  comparisons and blocking rules.
- **`il_model`** — spec bound to data and a DBI connection. Holds
  trained parameters after estimation.
- **`il_compared`** — tibble subclass of scored record pairs. Carries
  model metadata as attributes.

The interface document includes 36+ worked examples, end-to-end
workflows, an API reference table, and a section on lessons adopted
from gt's modern API patterns.

See: `04-irelink-core-interface.md`, especially §11 (end-to-end
examples) and §14 (lessons from gt).

### Stub files and roxygen documentation (2c)

47 R source files were created with 71 exported functions (plus 6
internal class utilities). Every exported function has:

- A stub body: `cli::cli_warn("Function {.fn name} is not yet
  implemented."); invisible(NULL)`
- Complete roxygen documentation: title, description, `@param`,
  `@return`, `@export`, and `@examples` (in `\dontrun{}`).

The package loads cleanly with `devtools::load_all()`.
`devtools::document()` generates 70 `.Rd` files in `man/` and a
complete NAMESPACE with all 71 exports.

See: `05-file-function-structure.md` (file map),
`06-function-draft-documentation.md` (conventions).

### Feature coverage audit (2c continued)

The 71-export stub set was verified against splink's ~233 functions.
Four core gaps were identified and filled with new stubs:

| New function | Covers |
|-------------|--------|
| `il_deterministic_link()` | Exact-match linking without training |
| `il_estimate_m_from_column()` | Train m from a ground-truth column |
| `il_cleanup()` | Remove temporary database tables |
| `il_unlinkables()` | Unlinkable-records diagnostic curve |

13 categories of features were documented as deferred, with priority
ratings from Medium (column transformers, blocking optimisation) to
Very Low (raw SQL wrappers).

See: `07-features-for-later.md`.

### Implementation sprints (2d)

The 71 exports were organised into 10 sprints with strict dependency
ordering. Each sprint has:

- A clear goal and preamble.
- A table of functions with file, visibility, and purpose.
- A "what a user can do after this sprint" section with example code.
- Key test targets for the tests-first approach.
- Implementation notes where needed.

The sprint sequence:

| Sprint | Focus | Exports | Milestone |
|--------|-------|---------|-----------|
| 1 | S3 classes, `il_spec()`, unit helpers | 14 | Data structures |
| 2 | All `cl_*()` comparison helpers | 24 | Comparison definitions |
| 3 | `il_compare()`, `il_block_on()` | 3 | Full specs |
| 4 | `il_demo()`, `il_string_similarity()` | 2 | Test data |
| 5 | SQL engine + exploration | 3 + engine | Database queries |
| 6 | `il_model()`, `il_cleanup()` | 5 | Model objects |
| 7 | EM training, `il_weights()`, `il_parameters()` | 8 | Statistical core |
| 8 | `predict()`, deterministic link, waterfall | 5 | **MVP** |
| 9 | `il_cluster()`, `il_graph_metrics()` | 2 | Entity clusters |
| 10 | Evaluation, autoplot, save/load | 9 | Feature-complete |

Sprint 8 is the MVP milestone: after it, the full
spec → train → predict pipeline works end-to-end.

See: `08-sprints.md`.

### Implementation plan (2e)

A detailed plan for Stages 3–7 was written, covering:

- **Stage 3 (Tests):** test-file structure, test targets per sprint,
  DuckDB integration test setup, expected test count (100+).
- **Stage 4 (Implementation):** sprint-by-sprint implementation
  details including EM algorithm pseudocode, SQL generation
  architecture, backend dialect registry, DESCRIPTION dependency
  additions per sprint.
- **Stage 5 (Simplification):** deduplication targets, style
  enforcement, dead code removal.
- **Stage 6 (Test review):** R-specific type safety tests, tidyverse
  integration tests, backend compatibility matrix, snapshot tests.
- **Stage 7 (Performance):** benchmarking against splink, profiling
  strategy, memory profiling, optimisation targets.

See: `09-implementation-plan.md`.

## Key decisions made during Stage 2

1. **S3 over R6.** Functional copy-on-modify semantics are more
   pipe-friendly and more consistent with the tidyverse ecosystem.
   This was the primary open question from Stage 1.

2. **`|>` over `+`.** Following gt's modern pattern rather than
   ggplot2's legacy pattern. Every builder function takes the object
   first and returns the same class.

3. **Tidyselect for column targeting.** `il_compare(c(first_name,
   last_name), cl_jaro_winkler(0.9))` follows gt's `columns`
   convention.

4. **Accumulation without replacement.** Multiple `il_compare()` and
   `il_block_on()` calls append, never overwrite. This matches gt
   and ggplot2 layer semantics.

5. **Data extraction over pre-rendered charts.** Visualisation
   functions return tibbles; `autoplot()` provides convenience plots.
   Users pipe to `ggplot()` for customisation.

6. **DuckDB as primary backend.** Other backends (SQLite, Postgres)
   are deferred to Stage 6 test review.

7. **Tests first.** Stage 3 writes all tests before Stage 4
   implements any function.

## Open items for Stage 3

- Set up `testthat` infrastructure.
- Decide on snapshot test directory structure.
- Generate or import demo datasets (`fake_1000`, `fake_1000_labels`).
- Decide on `months()` naming conflict resolution strategy
  (mask `base::months()` vs rename to `il_months()`).

## Package state at end of Stage 2

```
47 R source files
71 exported functions (all stubs)
6  internal class utilities (all stubs)
70 .Rd documentation files
0  tests (Stage 3)
0  implemented functions (Stage 4)

DESCRIPTION Imports: cli, tibble
```
