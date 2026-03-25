# Implementation Plan — Stages 3–7

> Detailed plan for taking irelink from a fully stubbed, documented
> package to a complete, tested, performant record-linkage library.
>
> **Prerequisites:** All Stage 1–2 work is complete. The package has 47
> R files, 71 exported stubs with roxygen documentation, an S3-based
> interface design (`inst/refs/04-irelink-core-interface.md`), and a
> 10-sprint implementation sequence (`inst/refs/08-sprints.md`).
>
> **Key references:**
>
> | Document | Contents |
> |----------|----------|
> | `01-what-splink-does.md` | Splink architecture, pipeline, backends |
> | `02-splink-and-r-deps.md` | R dependency mapping, dbplyr feasibility |
> | `03-splink-functions.md` | Complete splink function catalog (~233 items) |
> | `04-irelink-core-interface.md` | Interface design, examples, gt patterns |
> | `05-file-function-structure.md` | File → function map (47 files, 71 exports) |
> | `06-function-draft-documentation.md` | Roxygen conventions |
> | `07-features-for-later.md` | Deferred features and priorities |
> | `08-sprints.md` | 10 sprints with dependency ordering |
> | `stage-01-notes.md` | Stage 1 executive summary |
> | `../splink` | Local copy of splink source for reference |

---

## Stage 3 — Test Implementation

### Goal

Write every test *before* any function has a real implementation. Tests
should describe the expected behaviour of the interface defined in
`04-irelink-core-interface.md`. When every test is written, the test
suite is a complete behavioural specification for irelink.

### Approach

Tests follow the sprint sequence in `08-sprints.md`. Each sprint's
functions get their own test file(s). The testing framework is
`testthat` (edition 3).

### 3a. Set up testthat infrastructure

- Run `usethis::use_testthat(edition = 3)` if not already configured.
- Add `testthat (>= 3.0.0)` to `Suggests` in DESCRIPTION.
- Create `tests/testthat.R` entry point.
- Configure snapshot test directory if snapshot tests are needed.

### 3b. Write tests — Sprint 1 (Foundation)

**Files:** `test-il_spec.R`, `test-unit-helpers.R`, `test-classes.R`

| Test | What it verifies |
|------|-----------------|
| `il_spec()` returns `il_spec` class | Object creation |
| `is_il_spec(il_spec())` is `TRUE` | Type checking |
| `is_il_spec("not a spec")` is `FALSE` | Type rejection |
| `print(il_spec())` produces output | Print method |
| `days(30)` creates tagged value | Unit helper structure |
| `km(5)` creates tagged value | Unit helper structure |
| `months(3)` creates tagged value | Conflicting-name helper |
| Validators reject malformed objects | Internal integrity |

### 3c. Write tests — Sprint 2 (Comparison Helpers)

**Files:** `test-cl-similarity.R`, `test-cl-levels.R`, `test-cl-domain.R`

| Test | What it verifies |
|------|-----------------|
| `cl_exact()` creates a comparison level object | Constructor |
| `cl_jaro_winkler(0.9, 0.7)` stores thresholds descending | Threshold ordering |
| `cl_jaro_winkler(0.7, 0.9)` warns about non-descending order | Input validation |
| `cl_date_diff(days(30))` accepts unit helpers | Integration |
| `cl_levels(cl_null(), cl_exact(), cl_else())` nests correctly | Composition |
| `cl_and(cl_exact(), cl_jaro_winkler(0.9))` creates AND node | Boolean composition |
| `cl_name()` returns the same structure as manual composition | Domain bundle equivalence |
| Negative thresholds are rejected | Input validation |

### 3d. Write tests — Sprint 3 (Spec Composition)

**Files:** `test-il_compare.R`, `test-il_block_on.R`

| Test | What it verifies |
|------|-----------------|
| `il_spec() \|> il_compare(name, cl_exact())` returns `il_spec` | Pipe-friendliness |
| Two `il_compare()` calls accumulate | Accumulation |
| Tidyselect: `c(first_name, last_name)` works | Column selection |
| Tidyselect: `starts_with("addr_")` works | Column selection |
| `il_block_on(spec, first_name)` adds a blocking rule | Blocking |
| Two `il_block_on()` calls OR together | Accumulation |
| `block_on(first_name, surname)` creates standalone rule | Training rules |
| Passing non-spec to `il_compare()` errors | Type safety |
| `print()` output shows comparisons and blocking rules | Print |

### 3e. Write tests — Sprint 4 (Demo Data & String Similarity)

**Files:** `test-il_demo.R`, `test-il_string_similarity.R`

| Test | What it verifies |
|------|-----------------|
| `il_demo("fake_1000")` returns a tibble | Data loading |
| Result has expected columns | Schema |
| `il_demo()` with no argument lists datasets | Discovery |
| Invalid name errors | Input validation |
| `il_string_similarity("Robert", "Robt")` returns tibble | Similarity computation |
| Known string pairs produce expected scores | Correctness |
| Identical strings return 1.0 for all metrics | Edge case |
| `NA` input is handled gracefully | Edge case |

### 3f. Write tests — Sprint 5 (SQL Engine & Exploration)

**Files:** `test-sql-generate.R`, `test-sql-blocking.R`,
`test-il_completeness.R`, `test-il_profile.R`, `test-il_count_pairs.R`

These require a DuckDB connection for integration testing.

| Test | What it verifies |
|------|-----------------|
| `cl_exact()` on `"name"` → correct SQL fragment | SQL generation |
| `cl_jaro_winkler(0.9)` → CASE with `jaro_winkler_similarity` | SQL generation |
| `cl_date_diff(days(30))` → correct date arithmetic SQL | SQL generation |
| `block_on(first_name)` → `l."first_name" = r."first_name"` | SQL generation |
| Multiple blocking rules → OR in WHERE clause | SQL generation |
| `il_completeness(df, con = con)` → correct pct_non_null | Integration |
| `il_profile(df, name, con = con)` → value counts | Integration |
| `il_count_pairs(df, block_on(name), con = con)` → accurate count | Integration |

### 3g. Write tests — Sprint 6 (Model Creation)

**Files:** `test-il_model.R`, `test-il_cleanup.R`

| Test | What it verifies |
|------|-----------------|
| `il_model(df, spec = spec, con = con)` → `il_model` class | Creation |
| Missing column in spec → informative error | Validation |
| `link_type = "link"` requires two datasets | Validation |
| `print()` shows records, comparisons, status | Print |
| `summary()` shows "untrained" | Summary |
| `il_cleanup(model)` removes temp tables | Cleanup |

### 3h. Write tests — Sprint 7 (Training)

**Files:** `test-il_estimate.R`, `test-il_weights.R`,
`test-il_parameters.R`

| Test | What it verifies |
|------|-----------------|
| `il_estimate_u()` → u values near 0 for exact matches | Correctness |
| `il_estimate_em()` → parameters converge on known data | Convergence |
| Multiple EM calls refine, not reset | Accumulation |
| `il_estimate_prior()` → valid probability | Correctness |
| `il_weights()` → tibble with comparison, level, weight | Output shape |
| `il_parameters()` → tibble with m, u in [0, 1] | Output shape |
| `il_training_history()` → values converge over iterations | Convergence |

### 3i. Write tests — Sprint 8 (Prediction)

**Files:** `test-predict.R`, `test-il_deterministic_link.R`,
`test-il_waterfall.R`

| Test | What it verifies |
|------|-----------------|
| `predict(model)` → `il_compared` tibble | Output class |
| Threshold filtering excludes low-probability pairs | Filtering |
| Known planted duplicates are found | Correctness |
| `il_deterministic_link()` → exact matches without training | Correctness |
| `il_compare_records()` → expected gamma vector | Correctness |
| `il_waterfall()` → contributions sum to total weight | Consistency |

### 3j. Write tests — Sprint 9 (Clustering)

**Files:** `test-il_cluster.R`, `test-il_graph_metrics.R`

| Test | What it verifies |
|------|-----------------|
| A-B + B-C → one cluster of three records | Connected components |
| Threshold re-filtering before clustering | Threshold |
| `method = "best_link"` → one record per dataset per cluster | Best-link |
| `il_graph_metrics()` → three tibbles with correct metrics | Graph metrics |

### 3k. Write tests — Sprint 10 (Evaluation, Visualisation, Serialisation)

**Files:** `test-il_accuracy.R`, `test-il_roc.R`, `test-autoplot.R`,
`test-il_save.R`

| Test | What it verifies |
|------|-----------------|
| `il_accuracy()` → correct TP/FP/TN/FN at known thresholds | Correctness |
| `il_errors()` → correct FP/FN record pairs | Correctness |
| `il_roc()` → fpr and tpr in [0, 1] | Output shape |
| `il_precision_recall()` → precision and recall in [0, 1] | Output shape |
| `il_unlinkables()` → monotonically increasing with threshold | Monotonicity |
| `autoplot(model)` → ggplot object | Output class |
| `autoplot(pairs)` → ggplot object | Output class |
| `il_save()` + `il_load()` round-trip | Serialisation |

### 3l. Tag every test with its sprint

Use `testthat` context or file naming to make sprint membership clear.
When a sprint's implementation is done, its tests should all pass.
Running the full suite after each sprint shows cumulative progress.

### Stage 3 deliverable

A complete test suite with 100+ tests, all initially failing (or
skipped). The tests collectively serve as the behavioural specification
for the package. Every test references the expected interface from
`04-irelink-core-interface.md`.

---

## Stage 4 — R Code Implementation

### Goal

Implement every function, sprint by sprint, until all tests pass. This
is the largest stage and follows the 10-sprint sequence defined in
`08-sprints.md`.

### Approach

For each sprint:

1. Mark the sprint's tests as active (un-skip if previously skipped).
2. Implement the functions until the tests pass.
3. Run `R CMD check` to verify no regressions.
4. Update roxygen documentation if signatures changed.
5. Commit and tag.

### 4a. Sprint 1 — Foundation (S3 classes, `il_spec`, unit helpers)

**Reference:** `08-sprints.md` Sprint 1 (14 functions)

Implementation details:

- **S3 class constructors** (`new_il_spec()`, `new_il_model()`,
  `new_il_compared()`): use `structure()` with named list components.
  `il_spec` stores `comparisons` (list), `blocking_rules` (list),
  and `metadata` (list). `il_model` extends this with `data_ref`,
  `con`, `link_type`, `parameters`, `training_log`. `il_compared`
  is a tibble subclass with an `attr` for model metadata.
- **Validators**: check class, required components, types. Use
  `cli::cli_abort()` for errors.
- **Unit helpers**: return a list with `class` = `"il_days"` (etc.)
  and `value` = the numeric input. Print method shows `"30 days"`.
- **`months()` conflict**: name the function `months` and document
  the masking. Consider `il_months()` as an alternative if the
  collision causes problems.

Key decisions:

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Class system | S3 (not R6) | Functional semantics, copy-on-modify, pipe-friendly |
| Spec storage | Named list with class attribute | Simple, inspectable, serialisable |
| Unit helper class | Subclassed list | Allows `is.il_days()` type checking |

### 4b. Sprint 2 — Comparison Helpers (24 exports)

**Reference:** `08-sprints.md` Sprint 2

Implementation details:

- Each `cl_*()` returns a list of class `"il_comparison_level"` with
  fields: `method` (character), `thresholds` (numeric vector),
  `options` (named list), `levels` (for composition).
- Thresholds are validated: must be numeric, non-negative, and in
  descending order (warn if not, reorder silently).
- `cl_custom(sql_expr)` stores the raw SQL expression as a character
  string. No validation of SQL syntax at this stage.
- `cl_levels()` validates ordering: `cl_null()` must be first if
  present; `cl_else()` must be last if present.
- Domain bundles (`cl_name()`, `cl_dob()`, etc.) call the underlying
  `cl_*()` functions. They may accept customisation arguments
  (e.g., `cl_name(jw_threshold = 0.88)`).

### 4c. Sprint 3 — Spec Composition (3 exports)

**Reference:** `08-sprints.md` Sprint 3

Implementation details:

- **`il_compare(spec, col, method, ...)`**: uses `rlang::enquo()`
  and tidyselect to capture column expressions. Stores them
  unevaluated in the spec; resolution against actual data is deferred
  to `il_model()` (Sprint 6). Appends to `spec$comparisons`.
- **`il_block_on(spec, ..., .where)`**: captures column expressions.
  Appends to `spec$blocking_rules`. Each call adds one rule; rules
  are OR-ed at prediction time.
- **`block_on(...)`**: does *not* take a spec. Returns a standalone
  `il_blocking_rule` object for use in `il_estimate_em()` and
  `il_estimate_prior()`.
- **Print update**: `print.il_spec()` now iterates over
  `spec$comparisons` and `spec$blocking_rules` to produce a
  readable summary.

Key dependency: `rlang` must be added to Imports for tidyselect
and quosure support.

### 4d. Sprint 4 — Demo Data & String Similarity (2 exports)

**Reference:** `08-sprints.md` Sprint 4

Implementation details:

- **`il_demo()`**: load datasets from `inst/extdata/`. Source datasets
  from splink's `splink_datasets` module — translate to R tibbles
  stored as `.rds` files. Include at minimum:
  - `fake_1000` — 1000 records with planted duplicates (deduplication)
  - `fake_1000_links` — two tables for linkage tasks
  - `fake_1000_labels` — ground-truth pairwise labels for evaluation
  - `febrl3` — the Freely Extensible Biomedical Record Linkage
    dataset (standard benchmark)
- **`il_string_similarity()`**: pure R, no database. Compute
  Jaro-Winkler, Jaro, Levenshtein, Jaccard, and Cosine similarity
  using the `stringdist` package (Suggests) with a fallback to a
  minimal built-in implementation if `stringdist` is not installed.

### 4e. Sprint 5 — SQL Engine & Exploration (3 exports + engine)

**Reference:** `08-sprints.md` Sprint 5

This is the most engineering-intensive sprint. The SQL engine is the
backbone of Sprints 6–10.

Implementation details:

**Internal SQL generation (new files):**

| File | Responsibility |
|------|---------------|
| `R/utils-sql-generate.R` | Translate `il_comparison_level` objects into SQL CASE expressions. Each comparison becomes a gamma column (`gamma_first_name`, etc.) with integer levels. |
| `R/utils-sql-blocking.R` | Translate blocking rules into SQL WHERE/JOIN conditions. Handle OR-composition across rules and AND-composition within a rule. |
| `R/utils-sql-cte.R` | CTE pipeline builder. Collect named SQL fragments and emit a single `WITH cte_1 AS (...), cte_2 AS (...) SELECT ...` statement. |
| `R/utils-sql-backend.R` | Backend dialect registry. Map abstract function names (e.g., `"jaro_winkler"`) to backend-specific SQL (e.g., DuckDB's `jaro_winkler_similarity()`). |

**SQL generation strategy:**

- Use `dbplyr` for basic table operations (joins, filters, selects,
  aggregations) where possible.
- Use `glue::glue_sql()` for templated SQL construction where dbplyr
  cannot express the operation (string similarity functions, CASE
  expressions with backend-specific functions).
- The dialect registry maps operations to SQL fragments per backend.
  Start with DuckDB only; add SQLite and Postgres in Stage 5.

**Backend registry structure:**

```r
# Internal: registered dialects
il_dialects <- list(
  duckdb = list(
    jaro_winkler = "jaro_winkler_similarity({l}, {r})",
    levenshtein  = "levenshtein({l}, {r})",
    jaccard      = "jaccard({l}, {r})",
    damerau_levenshtein = "damerau_levenshtein({l}, {r})",
    log2         = "log2({x})",
    greatest     = "greatest({a}, {b})",
    least        = "least({a}, {b})"
  )
  # sqlite, postgres, spark to follow
)
```

**Exploration functions:**

- `il_completeness()`: for each column, compute
  `COUNT(col) / COUNT(*) * 100`. Use dbplyr `summarise()` if data
  is a `tbl_lazy`; use base R if data is a local data frame.
- `il_profile()`: top-N value counts per column. Use dbplyr
  `count()` + `slice_max()`.
- `il_count_pairs()`: for each blocking rule, compute the number
  of pairs it would generate. Use the blocking-rule SQL to compute
  a self-join count.

Key dependency: `glue` and `dplyr`/`dbplyr` must be added to Imports.

### 4f. Sprint 6 — Model Creation (5 exports)

**Reference:** `08-sprints.md` Sprint 6

Implementation details:

- **`il_model()`**:
  1. Accept one data frame (dedupe) or two (link / link_and_dedupe).
  2. Resolve tidyselect column expressions from the spec against the
     actual data columns. Error if columns are missing.
  3. Upload data to the DBI connection as temporary tables (using
     `DBI::dbWriteTable()` with `temporary = TRUE` or
     `dplyr::copy_to()`).
  4. Detect the backend dialect from the connection class
     (`duckdb_connection`, `SQLiteConnection`, `PqConnection`, etc.).
  5. Build the `il_model` object with: spec, data references (table
     names in the DB), connection, link_type, dialect, and an empty
     parameters slot.
- **`il_cleanup()`**: iterate over all temporary table names stored
  in the model and call `DBI::dbRemoveTable()`.
- **`print.il_model()`**: show record counts, number of comparisons,
  number of blocking rules, training status, and backend dialect.
- **`summary.il_model()`**: show all comparisons with their current
  parameter values (`NA` if untrained).

### 4g. Sprint 7 — Training & Model Inspection (8 exports)

**Reference:** `08-sprints.md` Sprint 7

This is the statistical core of the package. The EM algorithm is the
most complex piece.

Implementation details:

**EM algorithm (`il_estimate_em()`):**

1. **Generate comparison vectors** — SQL query that:
   - Applies the blocking rule (WHERE clause from `block_on()`).
   - Computes gamma columns (CASE expressions from Sprint 5's SQL
     engine) for each comparison.
   - Groups by the distinct gamma patterns and counts occurrences.
2. **Initialise** — set initial m/u values (m = 0.9 for exact, 0.1
   for non-exact; u = 0.1 for all; or from prior training).
3. **E-step** — for each gamma pattern, compute:
   ```
   p(match | gamma) = (prior * prod(m_j^gamma_j * (1-m_j)^(1-gamma_j))) /
                      (prior * prod(m_j^...) + (1-prior) * prod(u_j^...))
   ```
4. **M-step** — re-estimate m and u as weighted proportions:
   ```
   m_j_new = sum(p(match) * count * I(gamma_j)) / sum(p(match) * count)
   u_j_new = sum((1-p(match)) * count * I(gamma_j)) / sum((1-p(match)) * count)
   ```
5. **Convergence** — repeat E-M until max parameter change < 1e-4
   or max iterations (25) reached.
6. **Store** — update `model$parameters` with final m/u values.
   Append iteration history to `model$training_log`.

**Key reference:** splink's `expectation_maximisation.py` and
`em_training_session.py`.

**Other training functions:**

- `il_estimate_u()`: generate random pairs (no blocking or very loose
  blocking), compute gamma vectors, estimate u as the proportion of
  pairs in each level.
- `il_estimate_prior()`: use deterministic rules to find near-certain
  matches, then estimate prior = n_matches / n_possible_pairs,
  adjusted by the `recall` parameter.
- `il_estimate_m_from_labels()`: given a tibble of `(id_l, id_r,
  is_match)`, compute m directly as the proportion of true matches
  in each level.
- `il_estimate_m_from_column()`: given a column name, derive
  pairwise matches (records with the same value) and delegate to the
  label-based estimation.

**Inspection functions:**

- `il_weights()`: compute `log2(m/u)` for each level of each
  comparison. Return as tibble.
- `il_parameters()`: extract m and u values from `model$parameters`.
- `il_training_history()`: extract `model$training_log` as a tibble
  with columns `comparison`, `level`, `iteration`, `param`, `value`.

### 4h. Sprint 8 — Prediction & Pair Inspection (5 exports)

**Reference:** `08-sprints.md` Sprint 8

Implementation details:

- **`predict.il_model()`**:
  1. Build a SQL query that: joins blocked pairs (using all OR-ed
     blocking rules), computes gamma columns, calculates partial
     match weights (`log2(m/u)` per level), sums to total match
     weight, and converts to match probability
     (`1 / (1 + 2^(-weight))`).
  2. Filter by `threshold` (on match probability).
  3. Collect results as a tibble of class `il_compared`.
- **`il_deterministic_link()`**: like `predict()` but without
  probabilistic scoring — just return all blocked pairs that satisfy
  the blocking rules.
- **`il_compare_records()`**: take two records (lists or single-row
  tibbles), push to the database, compute gamma and weights, return
  a single-row `il_compared` tibble.
- **`il_find_matches()`**: take new records and a trained model, push
  new records to the DB, join against existing data with blocking
  rules, score, filter, and return.
- **`il_waterfall()`**: for a specific pair (by row index in the
  `il_compared` tibble), extract the gamma vector and compute each
  comparison's partial weight contribution.

### 4i. Sprint 9 — Clustering & Graph Metrics (2 exports)

**Reference:** `08-sprints.md` Sprint 9

Implementation details:

- **`il_cluster()`**:
  - Filter pairs by `threshold` (if different from predict-time
    threshold).
  - Build an igraph graph from `(id_l, id_r)` edges.
  - Run `igraph::components()` to get connected components.
  - For `method = "best_link"`: greedily pick the highest-weight
    edge per record, then run connected components on the reduced
    edge set.
  - Return a tibble with `record_id`, `source_dataset` (for link
    mode), and `cluster_id`.
- **`il_graph_metrics()`**:
  - Build igraph graph from pairs.
  - Compute node metrics: degree, betweenness, is_bridge.
  - Compute edge metrics: weight, is_bridge.
  - Compute cluster metrics: size, density, diameter,
    n_source_datasets.
  - Return named list of three tibbles.

Key dependency: `igraph` must be added to Imports.

### 4j. Sprint 10 — Evaluation, Visualisation & Serialisation (9 exports)

**Reference:** `08-sprints.md` Sprint 10

Implementation details:

- **Evaluation** (`il_accuracy`, `il_errors`, `il_roc`,
  `il_precision_recall`, `il_unlinkables`):
  - Accept a trained model and a labels tibble (with `id_l`, `id_r`,
    `is_match` columns).
  - Run `predict()` internally at multiple thresholds (or use the
    already-predicted pairs).
  - Compute TP/FP/TN/FN at each threshold.
  - Return tidy tibbles ready for ggplot2.
- **Autoplot** (`autoplot.il_model`, `autoplot.il_compared`):
  - `autoplot.il_model()` → call `il_weights(model)` and produce a
    faceted bar chart of partial match weights.
  - `autoplot.il_compared()` → histogram of `match_weight` column.
  - Both return ggplot objects (not printed — follows ggplot2
    convention).
- **Serialisation** (`il_save`, `il_load`):
  - Serialise model parameters, spec, and metadata to JSON (using
    `jsonlite::write_json()`).
  - Do NOT serialise the DBI connection or data — only the
    specification and trained parameters.
  - `il_load()` restores an `il_model` without a connection. Users
    must re-bind data and connection to use the loaded model for
    prediction.

Key dependency: `ggplot2` must be added to Imports. `jsonlite` must
be added to Imports for serialisation.

### 4k. DESCRIPTION updates across sprints

As implementation proceeds, dependencies must be added to DESCRIPTION:

| Sprint | New Imports | New Suggests |
|--------|-------------|--------------|
| 1 | (none — cli, tibble already present) | testthat (>= 3.0.0) |
| 2 | (none) | |
| 3 | rlang | |
| 4 | | stringdist |
| 5 | dplyr, dbplyr, glue, DBI | duckdb |
| 6 | (uses DBI from Sprint 5) | |
| 7 | (none) | |
| 8 | (none) | |
| 9 | igraph | |
| 10 | ggplot2, jsonlite | |

### Stage 4 deliverable

All 71 exports implemented. All tests from Stage 3 pass. `R CMD check`
passes with no errors and no warnings (notes are acceptable).

---

## Stage 5 — Code Simplification

### Goal

Review the implemented code for opportunities to simplify, reduce
duplication, and align with R idioms. The first implementation pass
(Stage 4) will prioritise correctness over elegance — this stage
corrects that.

### 5a. Identify repeated patterns

Scan all `R/` files for repeated code blocks. Common candidates:

- **SQL CASE generation**: all `cl_*()` helpers generate similar CASE
  WHEN expressions. Extract a shared `build_case_sql()` internal
  helper.
- **Threshold validation**: every `cl_*()` validates thresholds.
  Extract `validate_thresholds()`.
- **Table upload**: `il_model()`, `il_completeness()`,
  `il_count_pairs()`, etc. all need to upload data frames to the DB.
  Extract `ensure_db_table()`.
- **Parameter extraction**: `il_weights()`, `il_parameters()`,
  `il_training_history()` all reach into `model$parameters` and
  `model$training_log`. Ensure the accessor pattern is consistent.

### 5b. Consolidate SQL generation

Review the SQL engine files for:

- Template duplication across comparison types.
- Opportunities to use dbplyr more (reducing raw SQL).
- Places where `glue_sql()` can replace string concatenation.

### 5c. Simplify S3 methods

Check that all S3 methods follow consistent patterns:

- Print methods use `cli::cli_h1()`, `cli::cli_bullets()`,
  `cli::cli_alert_info()` for structured output.
- Summary methods return invisible tibbles (like `summary.lm()`
  returns an object that prints nicely).

### 5d. Remove dead code

Delete any internal helpers that were written during implementation
but are no longer used. Remove commented-out code.

### 5e. Style consistency

Run `styler::style_pkg()` to enforce consistent formatting. Verify
that the result matches the project conventions.

### Stage 5 deliverable

Cleaner, more maintainable code. No behaviour changes — all tests
still pass.

---

## Stage 6 — Test Review

### Goal

Fill in test gaps that splink's test suite would not cover because of
differences between Python and R. Add R-specific tests for type
safety, tidyverse integration, and edge cases.

### 6a. R type safety tests

| Area | What to test |
|------|-------------|
| Factor columns | Do comparisons handle factors correctly? (Coerce to character or error?) |
| Date columns | Do `cl_date_diff()` comparisons handle `Date`, `POSIXct`, and character dates? |
| Missing values | Are `NA`s handled at every stage? (spec building, comparison, prediction, clustering) |
| Zero-row data | Does the pipeline handle empty data frames gracefully? |
| Single-row data | Does deduplication with one record return zero pairs? |

### 6b. Tidyverse integration tests

| Area | What to test |
|------|-------------|
| Pipe chains | Full `il_spec() \|> ... \|> predict() \|> il_cluster()` pipeline |
| dplyr verbs on `il_compared` | `filter()`, `mutate()`, `group_by()`, `summarise()` on prediction output |
| ggplot2 integration | `il_weights() \|> ggplot(aes(...)) + geom_col()` produces a valid plot |
| tibble printing | `il_compared` prints like a tibble (truncated, with type annotations) |
| Tidyselect edge cases | `everything()`, `where(is.numeric)`, `matches("name")` in `il_compare()` |

### 6c. Backend compatibility tests

| Backend | What to test |
|---------|-------------|
| DuckDB | Full pipeline (primary backend) |
| SQLite | Full pipeline (limited string functions — verify fallbacks) |
| PostgreSQL | Connection + basic operations (if available in CI) |

For backends that lack string-similarity functions (SQLite), tests
should verify that:
- The package errors informatively when a comparison requires an
  unavailable function.
- `cl_exact()` and `cl_numeric_diff()` work on all backends.

### 6d. Snapshot tests

Add snapshot tests for:
- `print.il_spec()` output
- `print.il_model()` output (trained and untrained)
- `summary.il_model()` output
- SQL generated by each comparison type

These catch unintended changes to user-visible output.

### 6e. Performance-sensitive tests

Add tests that verify performance-critical operations complete in
reasonable time:
- `il_estimate_em()` on 1000 records completes in < 30 seconds.
- `predict()` on 1000 records completes in < 30 seconds.
- `il_cluster()` on 10,000 pairs completes in < 10 seconds.

Use `testthat::expect_no_error()` with `withr::local_options()` to
set timeouts.

### Stage 6 deliverable

A comprehensive test suite covering R-specific concerns. All tests
pass on at minimum DuckDB.

---

## Stage 7 — Performance Review

### Goal

Ensure that irelink is at least as fast as splink for equivalent
workloads. R should not be slower than Python for SQL-bottlenecked
operations; this stage verifies that and fixes any pure-R bottlenecks.

### 7a. Benchmark against splink

Create a benchmarking script (`inst/benchmarks/benchmark.R`) that
runs the full pipeline on the `fake_1000` dataset and records wall-
clock time for each stage:

| Stage | What to time |
|-------|-------------|
| Data upload | `il_model()` (table creation) |
| U estimation | `il_estimate_u()` |
| EM training | `il_estimate_em()` |
| Prediction | `predict()` |
| Clustering | `il_cluster()` |
| Full pipeline | End-to-end |

Compare against splink running the same pipeline in Python. The
expectation is that most time is spent in SQL, so irelink and splink
should be comparable. Any large discrepancy points to an R-side
bottleneck.

### 7b. Profile R-side code

Use `profvis::profvis()` to profile the EM algorithm implementation.
Look for:

- **Unnecessary data copies**: S3 copy-on-modify can cause large
  allocations if model objects are not carefully updated.
- **Row-by-row operations**: any `for` loops over records should be
  replaced with vectorised operations or SQL.
- **Repeated SQL execution**: check that SQL queries are batched
  appropriately (one query per EM iteration, not one per record).

### 7c. Optimise hot paths

Common optimisations:

| Pattern | Problem | Fix |
|---------|---------|-----|
| Data frame copying in EM loop | Memory pressure | Use in-place list modification or environments |
| R-side gamma computation | Slow for large datasets | Move entirely to SQL |
| `collect()` of full prediction table | Memory overflow | Stream results or use database-side filtering |
| igraph graph construction | Slow for millions of edges | Pre-filter edges in SQL before collecting |

### 7d. Memory profiling

For large datasets (100k+ records), check peak memory usage. The
primary concern is the prediction table — with N records and B
blocking rules, the number of pairs can be very large. Ensure that:

- Predictions are filtered in SQL (not collected then filtered in R).
- Clustering operates on the filtered pairs, not all pairs.
- Temporary database tables are cleaned up.

### 7e. Backend performance comparison

Run benchmarks on DuckDB and SQLite (at minimum). DuckDB should be
significantly faster for string-similarity operations. Document the
expected performance characteristics per backend.

### Stage 7 deliverable

Benchmarking results documented in `inst/benchmarks/`. Any
performance bottlenecks identified and fixed. R-side hot paths
verified as vectorised or SQL-delegated.

---

## Summary

| Stage | Focus | Key output |
|-------|-------|------------|
| 3 | Tests first | Complete test suite (100+ tests), all failing |
| 4 | Implementation | All 71 exports working, all tests passing |
| 5 | Simplification | Cleaner code, no behaviour changes |
| 6 | Test review | R-specific tests, backend compatibility |
| 7 | Performance | Benchmarks, profiling, optimisation |

### Implementation principles across all stages

1. **Tests describe behaviour.** Every function's expected input/output
   is captured in a test before the function is implemented.
2. **SQL does the heavy lifting.** R code orchestrates; the database
   executes. Minimise data movement between R and the database.
3. **dbplyr first, raw SQL second.** Use dbplyr for anything it can
   express. Use `glue_sql()` for backend-specific functions. Use
   `DBI::dbGetQuery()` only as a last resort.
4. **One sprint at a time.** Each sprint depends only on completed
   sprints. Do not skip ahead.
5. **`R CMD check` after every sprint.** No errors, no warnings.
6. **Copy nothing from splink.** Translate the *logic*, not the
   *code*. Use R idioms throughout.

### Imports at completion

```
Imports:
    cli,
    DBI,
    dplyr,
    dbplyr,
    ggplot2,
    glue,
    igraph,
    jsonlite,
    rlang,
    tibble
```

### Suggests at completion

```
Suggests:
    duckdb,
    plotly,
    RSQLite,
    RPostgres,
    stringdist,
    testthat (>= 3.0.0),
    withr
```
