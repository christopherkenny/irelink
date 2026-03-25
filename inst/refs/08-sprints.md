# 08 — Implementation Sprints

> Organises the 71 irelink exports (plus 6 internal constructors) into
> 10 sequential sprints. Each sprint depends only on earlier sprints.
> Every sprint has user-facing deliverables that can be tested.
>
> **Approach:** tests-first. For each sprint, write the tests that
> describe the expected behaviour, then implement the functions until the
> tests pass.
>
> Cross-references: `05-file-function-structure.md` (file map),
> `04-irelink-core-interface.md` (interface design),
> `07-features-for-later.md` (deferred features).

---

## Dependency Graph (visual summary)

```
Sprint 1  Foundation ─────────────────────────────┐
Sprint 2  Comparison Helpers ──────────────────────┤
Sprint 3  Spec Composition ────────────────────────┤
Sprint 4  Demo Data & String Similarity            │
Sprint 5  SQL Engine & Exploration ────────────────┤
Sprint 6  Model Creation ─────────────────────────┤
Sprint 7  Training & Model Inspection ─────────────┤
Sprint 8  Prediction & Pair Inspection ────────────┤
Sprint 9  Clustering & Graph Metrics ──────────────┤
Sprint 10 Evaluation, Visualisation & Serialisation┘
```

Sprints 1–3 form a chain (each depends on the last). Sprint 4 is
independent of Sprint 3 but provides data needed by Sprint 5+.
Sprints 5–10 form a strict chain.

---

## Sprint 1 — Foundation: Types, Spec Skeleton, and Unit Helpers

### Goal

Build the structural bones of the package: S3 class constructors, the
empty `il_spec()` entry point, and the unit-helper value constructors.
Nothing touches a database or does any computation — this sprint is
purely about defining data structures and verifying their contracts.

### What a user can do after this sprint

```r
library(irelink)

# Create and print a (still-empty) specification
spec <- il_spec()
print(spec)
is_il_spec(spec)

# Create tagged-value helpers
days(30)
km(5)
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `utils-classes.R` | `new_il_spec()` | internal | Low-level S3 constructor for `il_spec` |
| `utils-classes.R` | `validate_il_spec()` | internal | Validate `il_spec` structure |
| `utils-classes.R` | `new_il_model()` | internal | Low-level S3 constructor for `il_model` |
| `utils-classes.R` | `validate_il_model()` | internal | Validate `il_model` structure |
| `utils-classes.R` | `new_il_compared()` | internal | Low-level S3 constructor for `il_compared` |
| `utils-classes.R` | `validate_il_compared()` | internal | Validate `il_compared` structure |
| `il_spec.R` | `il_spec()` | exported | Create an empty linkage specification |
| `il_spec.R` | `print.il_spec()` | exported | Pretty-print a specification |
| `il_spec.R` | `is_il_spec()` | exported | Type check for `il_spec` |
| `utils-unit-helpers.R` | `days()` | exported | Tagged numeric: days |
| `utils-unit-helpers.R` | `months()` | exported | Tagged numeric: months |
| `utils-unit-helpers.R` | `years()` | exported | Tagged numeric: years |
| `utils-unit-helpers.R` | `km()` | exported | Tagged numeric: kilometres |
| `utils-unit-helpers.R` | `mi()` | exported | Tagged numeric: miles |

**Count:** 6 internal + 8 exported = **14 functions**

### Key test targets

- `il_spec()` returns an object of class `"il_spec"`
- `is_il_spec()` returns `TRUE` for specs, `FALSE` for everything else
- `print.il_spec()` produces human-readable output (snapshot test)
- Each unit helper returns a tagged list with the correct class and
  value (e.g., `days(30)` has class `"il_days"` and value `30`)
- Validators reject malformed objects with informative errors
- Bare numerics can still be used anywhere unit helpers are accepted
  (backward compatibility)

---

## Sprint 2 — Comparison Helpers

### Goal

Implement all `cl_*()` functions as **pure data-structure constructors**.
These do not generate SQL yet — they produce list objects that describe
*what* comparison to perform. SQL generation comes in Sprint 5.

This sprint also implements the composition helpers (`cl_levels()`,
`cl_and()`, etc.) and the domain-knowledge bundles (`cl_name()`, etc.).

### What a user can do after this sprint

```r
# Build comparison definitions
cl_exact()
cl_jaro_winkler(0.9, 0.7)
cl_date_diff(days(30), days(365))
cl_distance_km(km(5), km(50))

# Compose custom level hierarchies
cl_levels(
  cl_null(),
  cl_exact(),
  cl_jaro_winkler(0.95),
  cl_jaro_winkler(0.88),
  cl_else()
)

# Use domain bundles
cl_name()
cl_email()

# Boolean composition
cl_and(cl_exact(), cl_jaro_winkler(0.9))
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `cl_exact.R` | `cl_exact()` | exported | Exact-match comparison level |
| `cl_jaro_winkler.R` | `cl_jaro_winkler()` | exported | Jaro-Winkler similarity |
| `cl_jaro_winkler.R` | `cl_jaro()` | exported | Jaro similarity |
| `cl_levenshtein.R` | `cl_levenshtein()` | exported | Levenshtein edit distance |
| `cl_levenshtein.R` | `cl_damerau_levenshtein()` | exported | Damerau-Levenshtein distance |
| `cl_jaccard.R` | `cl_jaccard()` | exported | Jaccard set similarity |
| `cl_cosine.R` | `cl_cosine()` | exported | Cosine similarity |
| `cl_date_diff.R` | `cl_date_diff()` | exported | Date/time difference |
| `cl_distance_km.R` | `cl_distance_km()` | exported | Geographic distance |
| `cl_numeric_diff.R` | `cl_numeric_diff()` | exported | Absolute numeric difference |
| `cl_numeric_diff.R` | `cl_pct_diff()` | exported | Percentage numeric difference |
| `cl_array_intersect.R` | `cl_array_intersect()` | exported | Array intersection cardinality |
| `cl_custom.R` | `cl_custom()` | exported | Arbitrary SQL expression |
| `cl_levels.R` | `cl_levels()` | exported | Compose ordered comparison levels |
| `cl_levels.R` | `cl_null()` | exported | Null-handling sentinel level |
| `cl_levels.R` | `cl_else()` | exported | Catch-all fallback level |
| `cl_levels.R` | `cl_and()` | exported | Boolean AND of conditions |
| `cl_levels.R` | `cl_or()` | exported | Boolean OR of conditions |
| `cl_levels.R` | `cl_not()` | exported | Boolean NOT of a condition |
| `cl_domain.R` | `cl_name()` | exported | Domain bundle: personal name |
| `cl_domain.R` | `cl_dob()` | exported | Domain bundle: date of birth |
| `cl_domain.R` | `cl_email()` | exported | Domain bundle: email address |
| `cl_domain.R` | `cl_forename_surname()` | exported | Domain bundle: forename + surname |
| `cl_domain.R` | `cl_postcode()` | exported | Domain bundle: postal code |

**Count: 24 exported functions**

### Key test targets

- Each `cl_*()` returns a list with class `"il_comparison_level"`
  (or similar) and the correct `method` field
- Thresholds are stored in descending order (strictest first);
  out-of-order input triggers a warning
- `cl_levels()` nests child levels in order; validates that `cl_null()`
  is first and `cl_else()` is last (if present)
- `cl_and()` / `cl_or()` wrap their arguments in a boolean node
- Domain bundles return the same structure as manually composed levels
  (e.g., `cl_name()` produces something equivalent to combining
  `cl_exact()` + `cl_jaro_winkler(0.9, 0.7)`)
- Unit helpers from Sprint 1 are accepted by threshold arguments
  (e.g., `cl_date_diff(days(30))` stores `30` with unit `"days"`)
- Invalid inputs (negative thresholds, wrong types) are rejected

---

## Sprint 3 — Spec Composition: Compare and Block

### Goal

Wire comparison helpers and blocking rules into the `il_spec` object.
After this sprint, a user can build a *complete specification* — the
declarative description of a linkage task — without touching data or a
database. This is the first sprint where the pipe-friendly API becomes
visible.

### What a user can do after this sprint

```r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname,    cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob,        cl_date_diff(days(30), days(365))) |>
  il_compare(city,       cl_exact()) |>
  il_compare(email,      cl_email()) |>
  il_block_on(first_name) |>
  il_block_on(surname)

print(spec)
# Linkage Specification
#   Comparisons (5):
#     first_name : jaro_winkler (0.9, 0.7)
#     surname    : jaro_winkler (0.9, 0.7)
#     dob        : date_diff (30d, 365d)
#     city       : exact
#     email      : email [domain bundle]
#   Blocking rules (2, OR-ed):
#     1. first_name
#     2. surname

# Standalone blocking rules for training
rule <- block_on(first_name, surname)
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_compare.R` | `il_compare()` | exported | Add a comparison to a spec (tidyselect columns) |
| `il_block_on.R` | `il_block_on()` | exported | Add a blocking rule to a spec |
| `il_block_on.R` | `block_on()` | exported | Create a standalone blocking rule (for training) |

**Count: 3 exported functions**

### Key test targets

- `il_compare()` takes an `il_spec` first and returns an `il_spec`
  (pipe-friendly)
- Tidyselect expressions work: bare name, `c()`, `starts_with()`,
  `where(is.character)` (column resolution deferred to model binding;
  spec stores the expression)
- Multiple `il_compare()` calls **accumulate** — never overwrite
- `il_block_on()` takes an `il_spec` first and returns an `il_spec`
- Multiple `il_block_on()` calls accumulate (OR semantics)
- `block_on()` does NOT take a spec — it creates a standalone rule
  (used as an argument to `il_estimate_em()` later)
- `print.il_spec()` now shows comparisons and blocking rules
- Passing a non-spec to `il_compare()` or `il_block_on()` errors
  informatively

---

## Sprint 4 — Demo Data and String Similarity

### Goal

Two standalone utilities that need no database. `il_demo()` bundles
synthetic datasets for testing and examples. `il_string_similarity()`
provides an R-native string-comparison utility. These are independent
of the spec layer but essential for testing everything that follows.

### What a user can do after this sprint

```r
# Load a demo dataset
df <- il_demo("fake_1000")
head(df)

# Compare two strings
il_string_similarity("Robert", "Robt")
#> # A tibble: 1 × 5
#>   jaro_winkler  jaro levenshtein jaccard cosine
#>          <dbl> <dbl>       <int>   <dbl>  <dbl>
#> 1        0.917 0.889           2   0.571  0.816
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_demo.R` | `il_demo()` | exported | Load a bundled demo dataset |
| `il_string_similarity.R` | `il_string_similarity()` | exported | Compute multiple similarity metrics for two strings |

**Count: 2 exported functions**

### Key test targets

- `il_demo("fake_1000")` returns a tibble with expected columns
  (`unique_id`, `first_name`, `surname`, `dob`, `city`, `email`)
- `il_demo()` with no argument lists available datasets
- Invalid dataset name errors informatively
- `il_string_similarity("hello", "helo")` returns a tibble with
  columns for each metric
- Known pairs produce correct scores (verified against `stringdist`)
- Edge cases: empty strings, `NA` inputs, identical strings

### Implementation notes

Demo data should be stored in `inst/extdata/` as `.rds` or `.csv` files.
The `fake_1000` dataset can be generated from splink's
`splink_datasets.fake_1000` or synthesised independently. Include at
least two demo datasets:
- `fake_1000` — 1000 records with duplicates (deduplication task)
- `fake_1000_links` — two 500-record tables (linkage task)

---

## Sprint 5 — SQL Engine and Exploration

### Goal

Build the internal SQL generation engine and deliver the first three
database-touching functions. This is the most engineering-heavy sprint:
the SQL engine translates comparison specs and blocking rules into
backend-specific SQL. It is the backbone of everything in Sprints 6–10.

The exploration functions (`il_completeness()`, `il_profile()`,
`il_count_pairs()`) serve as the first user-visible proof that the SQL
engine works. They are simpler than model training and provide immediate
diagnostic value.

### What a user can do after this sprint

```r
con <- DBI::dbConnect(duckdb::duckdb())
df <- il_demo("fake_1000")

# Column completeness
il_completeness(df, con = con) |>
  ggplot2::ggplot(ggplot2::aes(x = column, y = pct_non_null)) +
  ggplot2::geom_col() +
  ggplot2::coord_flip()

# Column profiling
il_profile(df, first_name, surname, con = con)

# Pair-count estimation for blocking rules
il_count_pairs(
  df,
  block_on(first_name),
  block_on(surname),
  con = con
)
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_completeness.R` | `il_completeness()` | exported | Column completeness (pct non-null) |
| `il_profile.R` | `il_profile()` | exported | Column value distributions |
| `il_count_pairs.R` | `il_count_pairs()` | exported | Count pairs for blocking rules |
| *(new internal files)* | SQL generation engine | internal | Translate specs → SQL |

**Count: 3 exported functions + internal engine**

### Internal engine components (new files)

These are not in the current stub inventory and will be created during
this sprint:

| File (suggested) | Purpose |
|------------------|---------|
| `R/utils-sql-generate.R` | Core SQL generation: comparison expressions, CASE statements, gamma columns |
| `R/utils-sql-blocking.R` | Blocking-rule SQL: equality conditions, OR/AND composition |
| `R/utils-sql-cte.R` | CTE pipeline builder: collect SQL fragments, emit `WITH ... SELECT` |
| `R/utils-sql-backend.R` | Backend-specific SQL functions: Jaro-Winkler, Levenshtein, etc. per dialect |

### Key test targets

- **SQL generation (unit tests on internal functions):**
  - `cl_exact()` on column `"name"` produces `l."name" = r."name"`
  - `cl_jaro_winkler(0.9)` produces a CASE with `jaro_winkler_similarity(l."name", r."name") >= 0.9`
  - `cl_date_diff(days(30))` produces `ABS(l."dob" - r."dob") <= 30`
  - Blocking rule `block_on(first_name)` produces `l."first_name" = r."first_name"`
  - Multiple blocking rules OR correctly
- **Exploration functions (integration tests with DuckDB):**
  - `il_completeness()` returns one row per column with correct `pct_non_null`
  - `il_profile()` returns top-N value counts for selected columns
  - `il_count_pairs()` returns accurate pair counts verified against
    a known small dataset (hand-calculated)

### Architecture notes

The SQL engine should use **dbplyr for basic table operations** and
**glue for SQL template assembly**. Backend-specific functions (e.g.,
DuckDB's `jaro_winkler_similarity`) should be registered in a dialect
registry, allowing new backends to be added by providing function
mappings. See `inst/refs/02-splink-and-r-deps.md` §2.2 for details.

---

## Sprint 6 — Model Creation

### Goal

Bind a spec, data, and DBI connection into an `il_model` object. The
model uploads data to the database, validates column references against
the actual data, and stores the state needed by training and prediction.

This sprint also implements `il_cleanup()` to remove temporary tables.

### What a user can do after this sprint

```r
con <- DBI::dbConnect(duckdb::duckdb())

spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname,    cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob,        cl_date_diff(days(30), days(365))) |>
  il_block_on(first_name) |>
  il_block_on(surname)

model <- il_model(il_demo("fake_1000"), spec = spec, con = con)
print(model)
summary(model)
is_il_model(model)

# Clean up when done
il_cleanup(model)
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_model.R` | `il_model()` | exported | Bind data + spec + connection |
| `il_model.R` | `print.il_model()` | exported | Pretty-print model state |
| `il_model.R` | `summary.il_model()` | exported | Summarise model (training status, parameters) |
| `il_model.R` | `is_il_model()` | exported | Type check for `il_model` |
| `il_cleanup.R` | `il_cleanup()` | exported | Remove temporary tables |

**Count: 5 exported functions**

### Key test targets

- `il_model()` returns an `il_model` object containing the spec,
  connection, and data reference
- Column names in the spec are validated against the data — missing
  columns produce a clear error
- `link_type = "dedupe"` accepts one dataset;
  `link_type = "link"` requires two datasets
- Data is uploaded to the database (temporary tables created)
- `print.il_model()` shows number of records, comparisons, blocking
  rules, and training status ("untrained")
- `summary.il_model()` shows all comparisons with their current
  parameter values (all NA before training)
- `il_cleanup()` removes all temporary tables from the database
- Model creation with an already-closed connection errors informatively

---

## Sprint 7 — Training and Model Inspection

### Goal

Implement the EM algorithm and all parameter-estimation functions. This
is the statistical core of the package. After this sprint, users can
train a model and inspect the learned parameters — the core value
proposition of probabilistic record linkage.

The model-inspection functions (`il_weights()`, `il_parameters()`,
`il_training_history()`) are included here so that training results are
immediately verifiable.

### What a user can do after this sprint

```r
model <- il_model(il_demo("fake_1000"), spec = spec, con = con) |>
  il_estimate_prior(block_on(first_name, surname, dob), recall = 0.7) |>
  il_estimate_u(max_pairs = 1e6) |>
  il_estimate_em(block_on(first_name, surname)) |>
  il_estimate_em(block_on(dob))

summary(model)

# Inspect parameters
il_weights(model)
il_parameters(model)

# Convergence diagnostics
il_training_history(model) |>
  ggplot2::ggplot(ggplot2::aes(x = iteration, y = value, color = level)) +
  ggplot2::geom_line() +
  ggplot2::facet_wrap(~ comparison, scales = "free_y")
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_estimate_u.R` | `il_estimate_u()` | exported | Estimate u parameters from random pairs |
| `il_estimate_em.R` | `il_estimate_em()` | exported | Train m/u via expectation-maximisation |
| `il_estimate_prior.R` | `il_estimate_prior()` | exported | Estimate global match probability |
| `il_estimate_m_from_labels.R` | `il_estimate_m_from_labels()` | exported | Train m from labelled pairs |
| `il_estimate_m_from_column.R` | `il_estimate_m_from_column()` | exported | Train m from a label column |
| `il_training_history.R` | `il_training_history()` | exported | EM convergence trace data |
| `il_weights.R` | `il_weights()` | exported | Match-weight tibble per level |
| `il_parameters.R` | `il_parameters()` | exported | m/u parameter tibble |

**Count: 8 exported functions**

### Key test targets

- **`il_estimate_u()`**: u values for exact-match columns are near 0;
  u values for loose comparisons are higher
- **`il_estimate_em()`**: on known synthetic data with planted
  duplicates, m values converge toward expected values; multiple EM
  calls refine (not reset) parameters
- **`il_estimate_prior()`**: prior probability is between 0 and 1;
  higher recall assumption → higher prior
- **`il_estimate_m_from_labels()`**: with a labelled-pairs tibble,
  m values match the observed match rates
- **`il_estimate_m_from_column()`**: with a ground-truth column,
  m values match the column-derived match rates
- **`il_weights()`**: returns a tibble with columns `comparison`,
  `level`, `m`, `u`, `match_weight`; weights sum correctly
- **`il_parameters()`**: returns a tibble with one row per level;
  all m and u values are in [0, 1]
- **`il_training_history()`**: returns a tibble with one row per
  iteration per level; values converge

### Implementation notes

The EM algorithm is the most complex piece of the package. Key
implementation details:

1. **Comparison vectors**: For each blocked pair, compute a gamma vector
   (integer comparison level per comparison column). This is done in SQL.
2. **E-step**: Compute match/non-match posterior probabilities for each
   distinct gamma pattern, given current m/u values.
3. **M-step**: Re-estimate m/u as weighted proportions across gamma
   patterns.
4. **Convergence**: Stop when the max change in any parameter falls
   below a threshold (default 1e-4) or after a max number of iterations
   (default 25).

Reference: splink's `expectation_maximisation.py` and
`em_training_session.py`.

---

## Sprint 8 — Prediction and Pair Inspection

### Goal

Score all candidate record pairs using trained parameters. This sprint
delivers `predict()` (the S3 generic), deterministic linking, single-
record matching, and the waterfall diagnostic. After this sprint, the
main end-to-end pipeline works.

### What a user can do after this sprint

```r
# Score all pairs
pairs <- predict(model, threshold = 0.85)
pairs

# Histogram of match weights
pairs |>
  ggplot2::ggplot(ggplot2::aes(x = match_weight)) +
  ggplot2::geom_histogram(binwidth = 1)

# Deterministic (exact-match) linking
exact <- il_deterministic_link(
  il_demo("fake_1000"), spec = spec, con = con
)

# Score two specific records
il_compare_records(
  list(first_name = "John", surname = "Smith", dob = "1985-01-15"),
  list(first_name = "Jon",  surname = "Smith", dob = "1985-02-15"),
  spec = spec, con = con
)

# Find matches for a new record
il_find_matches(model, new_records, threshold = 0.8)

# Decompose a single pair's score
il_waterfall(pairs, which = 1)
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `predict.R` | `predict.il_model()` | exported | Score all blocked pairs |
| `il_deterministic_link.R` | `il_deterministic_link()` | exported | Exact-match linking (no training) |
| `il_compare_records.R` | `il_compare_records()` | exported | Score two specific records |
| `il_find_matches.R` | `il_find_matches()` | exported | Match new records against trained data |
| `il_waterfall.R` | `il_waterfall()` | exported | Weight decomposition per pair |

**Count: 5 exported functions**

### Key test targets

- **`predict()`**: returns an `il_compared` tibble with columns
  `id_l`, `id_r`, `match_weight`, `match_probability`, plus `gamma_*`
  columns for each comparison
- Threshold filtering: `threshold = 0.9` excludes pairs below 0.9
  match probability
- Known planted duplicates in `fake_1000` are found with high
  match weights
- **`il_deterministic_link()`**: returns exact-match pairs without
  requiring trained parameters; result is a plain tibble
- **`il_compare_records()`**: scores a known pair and returns the
  expected gamma vector and match weight
- **`il_find_matches()`**: given a new record and a trained model,
  returns matches above the threshold
- **`il_waterfall()`**: for a specific pair, returns a tibble with
  one row per comparison showing the partial match weight
  contribution; contributions sum to the total match weight

### Milestone

**After Sprint 8, the complete spec → model → train → predict pipeline
works end-to-end.** A user can take two datasets, define comparisons,
train parameters, and get scored pairs. This is the minimum viable
product (MVP).

---

## Sprint 9 — Clustering and Graph Metrics

### Goal

Convert scored pairs into entity clusters using connected-component
analysis. This completes the standard linkage workflow: pairs become
entities. Graph metrics provide cluster-quality diagnostics.

### What a user can do after this sprint

```r
# Cluster predictions
clusters <- pairs |> il_cluster(threshold = 0.95)
clusters

# Alternative: single-best-link
clusters_sbl <- pairs |> il_cluster(method = "best_link")

# Graph diagnostics
metrics <- il_graph_metrics(pairs, clusters)
metrics$nodes
metrics$edges
metrics$clusters

# Downstream dplyr: how many records per cluster?
clusters |>
  dplyr::count(cluster_id, sort = TRUE)
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_cluster.R` | `il_cluster()` | exported | Cluster pairs into entities |
| `il_graph_metrics.R` | `il_graph_metrics()` | exported | Node, edge, and cluster diagnostics |

**Count: 2 exported functions**

### Key test targets

- **Connected components**: given pairs A-B and B-C, all three records
  share the same `cluster_id`
- **Threshold**: `il_cluster(threshold = 0.95)` re-filters pairs
  before clustering (only pairs ≥ 0.95 match probability are included)
- **Best-link**: each record appears in at most one cluster; ties are
  broken deterministically
- **`il_graph_metrics()`**: returns a named list with three tibbles
  (`nodes`, `edges`, `clusters`); node degree, edge weight, and cluster
  size are correct for known graph structures
- Single-record clusters (no matches) are included with `cluster_id`
  equal to the record's own ID

### Implementation notes

Use `igraph::graph_from_data_frame()` for connected-component analysis.
The `igraph` package should be added to Imports. For the best-link
method, a greedy algorithm picks the highest-weight edge for each node,
breaking ties by `id_l` (or similar deterministic key).

---

## Sprint 10 — Evaluation, Visualisation, and Serialisation

### Goal

The final sprint delivers quality assessment (with ground-truth labels),
convenience visualisation via `autoplot()`, and model persistence. After
this sprint, every stub function has a working implementation.

### What a user can do after this sprint

```r
# Load labels for evaluation
labels <- il_demo("fake_1000_labels")

# Accuracy analysis
il_accuracy(model, labels)
il_errors(model, labels, threshold = 0.9)

# ROC and precision-recall curves
il_roc(model, labels) |>
  ggplot2::ggplot(ggplot2::aes(x = fpr, y = tpr)) +
  ggplot2::geom_line() +
  ggplot2::geom_abline(linetype = "dashed")

il_precision_recall(model, labels) |>
  ggplot2::ggplot(ggplot2::aes(x = recall, y = precision)) +
  ggplot2::geom_line()

# Unlinkables curve
il_unlinkables(model) |>
  ggplot2::ggplot(ggplot2::aes(x = threshold, y = pct_unlinkable)) +
  ggplot2::geom_line()

# Convenience plots
autoplot(model)   # match-weights chart
autoplot(pairs)   # match-weight histogram

# Save and reload
il_save(model, "my_model.json")
model2 <- il_load("my_model.json")
```

### Functions

| File | Function | Visibility | Purpose |
|------|----------|------------|---------|
| `il_accuracy.R` | `il_accuracy()` | exported | Accuracy metrics across thresholds |
| `il_errors.R` | `il_errors()` | exported | False positive / negative identification |
| `il_roc.R` | `il_roc()` | exported | ROC curve data |
| `il_precision_recall.R` | `il_precision_recall()` | exported | Precision-recall curve data |
| `il_unlinkables.R` | `il_unlinkables()` | exported | Unlinkable records across thresholds |
| `autoplot.R` | `autoplot.il_model()` | exported | Match-weights bar chart |
| `autoplot.R` | `autoplot.il_compared()` | exported | Match-weight histogram |
| `il_save.R` | `il_save()` | exported | Serialise model to JSON |
| `il_save.R` | `il_load()` | exported | Deserialise model from JSON |

**Count: 9 exported functions**

### Key test targets

- **`il_accuracy()`**: with known labels and predictions, returns
  correct TP/FP/TN/FN counts at each threshold
- **`il_errors()`**: at a specific threshold, identifies the correct
  false positives and false negatives by record-pair IDs
- **`il_roc()`**: returns a tibble with `fpr` and `tpr` columns;
  AUC is computable from the data
- **`il_precision_recall()`**: returns a tibble with `precision` and
  `recall` columns; values are in [0, 1]
- **`il_unlinkables()`**: returns a tibble with `threshold` and
  `pct_unlinkable`; proportion increases monotonically with threshold
- **`autoplot.il_model()`**: returns a `ggplot` object (class check)
- **`autoplot.il_compared()`**: returns a `ggplot` object
- **`il_save()` + `il_load()`**: round-trip preserves all model
  parameters; `all.equal(il_load(il_save(model, f)), model)` holds
  for trained models

### Implementation notes

Evaluation functions require a labels tibble with at least two columns
identifying a pair (`id_l`, `id_r`) and a column indicating true match
status (`is_match` or `clerical_match_score`). The functions should
accept flexible column-name conventions (documented in `@param`).

`autoplot()` methods require `ggplot2` in Imports. They should be thin
wrappers: extract the data tibble (via `il_weights()` or the `pairs`
tibble itself), then build a ggplot. Users who want customisation can
call the data function directly and pipe to their own `ggplot()`.

---

## Summary Table

| Sprint | Name | Exports | Cumulative | Key deliverable |
|--------|------|---------|------------|-----------------|
| 1 | Foundation | 8 (+6 internal) | 8 | `il_spec()`, unit helpers, S3 classes |
| 2 | Comparison Helpers | 24 | 32 | All `cl_*()` constructors |
| 3 | Spec Composition | 3 | 35 | `il_compare()`, `il_block_on()` — full specs |
| 4 | Demo Data & Strings | 2 | 37 | `il_demo()`, `il_string_similarity()` |
| 5 | SQL Engine & Exploration | 3 (+engine) | 40 | SQL generation, `il_completeness()` |
| 6 | Model Creation | 5 | 45 | `il_model()`, `il_cleanup()` |
| 7 | Training & Inspection | 8 | 53 | EM algorithm, `il_weights()` |
| 8 | Prediction & Pairs | 5 | 58 | `predict()`, `il_deterministic_link()` — **MVP** |
| 9 | Clustering & Graph | 2 | 60 | `il_cluster()`, `il_graph_metrics()` |
| 10 | Eval, Viz & Serialisation | 9 | 69 | `il_accuracy()`, `autoplot()`, `il_save()` |

> **Note:** The 69 count excludes the `irelink-package.R` sentinel
> (which has no function body) and the `is_il_model()` / `is_il_spec()`
> checks which are counted with their parent files. The full export
> count including all S3 methods matches the 71 in the NAMESPACE.

---

## Cross-Sprint Dependencies

```
Sprint 1 ← Sprint 2 ← Sprint 3
                                 ╲
Sprint 4 (independent) ──────────── Sprint 5 ← Sprint 6 ← Sprint 7 ← Sprint 8 ← Sprint 9 ← Sprint 10
```

- **Sprints 1–3** form the spec-building chain. Each depends on the
  prior sprint's data structures.
- **Sprint 4** is independent (no database, no spec needed) but its
  demo data is used by Sprint 5+ for integration tests.
- **Sprints 5–10** form the execution chain. Each depends on the
  prior sprint's infrastructure.
- **Sprint 8 is the MVP milestone.** After Sprint 8, the full
  spec → model → train → predict pipeline is functional.

---

## Testing Strategy Per Sprint

Each sprint follows the same test-first cycle:

1. **Write tests** that describe the expected behaviour (inputs,
   outputs, error conditions).
2. **Implement** the functions until tests pass.
3. **Run `R CMD check`** to verify no regressions.
4. **Update documentation** if implementation changes signatures.

Test files follow the convention `tests/testthat/test-{sprint-topic}.R`
or `tests/testthat/test-{function-name}.R` for larger functions.

| Sprint | Suggested test files |
|--------|---------------------|
| 1 | `test-il_spec.R`, `test-unit-helpers.R`, `test-classes.R` |
| 2 | `test-cl-similarity.R`, `test-cl-levels.R`, `test-cl-domain.R` |
| 3 | `test-il_compare.R`, `test-il_block_on.R` |
| 4 | `test-il_demo.R`, `test-il_string_similarity.R` |
| 5 | `test-sql-generate.R`, `test-sql-blocking.R`, `test-il_completeness.R`, `test-il_profile.R`, `test-il_count_pairs.R` |
| 6 | `test-il_model.R`, `test-il_cleanup.R` |
| 7 | `test-il_estimate.R`, `test-il_weights.R`, `test-il_parameters.R` |
| 8 | `test-predict.R`, `test-il_deterministic_link.R`, `test-il_waterfall.R` |
| 9 | `test-il_cluster.R`, `test-il_graph_metrics.R` |
| 10 | `test-il_accuracy.R`, `test-il_roc.R`, `test-autoplot.R`, `test-il_save.R` |
