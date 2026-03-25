# irelink Core Interface Design

> This document defines the user-facing R interface for irelink.
> The design follows tidyverse conventions so that the package feels native
> to analysts who already use dplyr, ggplot2, DBI, and gt.

---

## 1 Design Principles

Six rules govern every public function in irelink:

1. **Data first.** The primary object is always the first argument, enabling
   the native pipe operator (`|>`). This mirrors every modern Posit package:
   dplyr puts the data frame first (`filter(df, ...)`), gt puts the table
   first (`tab_header(data, ...)`), and irelink puts the spec or model first.

2. **Verbs describe actions.** Functions are named as imperative verbs:
   `il_compare()`, `il_block_on()`, `il_estimate_u()`. dplyr uses the same
   convention (`filter()`, `mutate()`, `summarise()`).

3. **Tibbles in, tibbles out.** Predictions and clusters are returned as
   plain tibbles. Users should never need to learn a custom container; results
   flow directly into dplyr, ggplot2, or any other tidyverse tool.

4. **Specification helpers.** Small constructor functions (`cl_exact()`,
   `cl_jaro_winkler()`, `days()`, `km()`) build declarative objects that
   describe *what* to do, not *how*. This is the same role `aes()` plays in
   ggplot2, `join_by()` plays in dplyr, and `cell_text()` / `cells_body()`
   play in gt.

5. **Familiar generics.** Standard S3 generics — `predict()`, `print()`,
   `summary()`, `autoplot()` — work on irelink objects. A user who knows how
   `predict(lm_fit, newdata = ...)` works already knows how
   `predict(il_model, ...)` works.

6. **Pure pipes, no `+`.** irelink uses `|>` throughout, following gt's
   modern convention rather than ggplot2's `+` operator. Every builder
   function takes the object as its first argument and returns the same
   class, so pipes chain without operators or wrapper calls.

---

## 2 Core Types

irelink introduces three S3 classes. Everything else is a tibble.

| Class | Role | Tidyverse analogy |
|-------|------|-------------------|
| `il_spec` | Declarative description of comparisons and prediction blocking rules | A ggplot object before you add data — layers of intent |
| `il_model` | A spec bound to data and a DBI connection; can be untrained or trained | A tidymodels `workflow` — bundles preprocessing + model + engine |
| `il_compared` | A tibble subclass carrying scored record pairs plus a reference back to the model that produced them | Like a tibble returned by `predict()` in tidymodels, carrying metadata |

The first two accumulate configuration and are pipe-friendly. The third is
a tibble that works everywhere tibbles do but knows enough about its
origin to support convenience methods like `il_cluster()` and
`il_waterfall()`.

---

## 3 The Specification Layer

### 3.1 Building a spec

`il_spec()` creates an empty specification. Comparisons and blocking
rules are added with pipe-friendly verbs, just as ggplot layers are added
with `+`.

```r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname,    cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob,        cl_date_diff(days(30), days(365))) |>
  il_compare(city,       cl_exact(term_frequency = TRUE)) |>
  il_compare(email,      cl_email()) |>
  il_block_on(first_name) |>
  il_block_on(surname)
```

Each `il_compare()` call is a layer that says "compare this column using
this method." Each `il_block_on()` call adds a prediction-blocking rule.
The spec records these declarations without touching any data.

#### Comparison to ggplot2 and gt

irelink's specification layer draws from both ggplot2 and gt. Like
ggplot2, it accumulates declarative layers. Like gt, it uses `|>` pipes
(not `+`) and tidyselect for column targeting.

| Package | Pattern | irelink equivalent |
|---------|---------|-------------------|
| ggplot2 | `ggplot()` creates an empty canvas | `il_spec()` creates an empty spec |
| ggplot2 | `aes(x = ..., y = ...)` declares aesthetics | `cl_jaro_winkler(0.9)` declares a method |
| ggplot2 | `+ geom_point()` adds a layer | `\|> il_compare(col, cl_*())` adds a comparison |
| gt | `gt(data)` creates from data, then pipe | `il_spec() \|> il_compare() \|> ...` pure pipe chain |
| gt | `tab_header(data, ...)` always returns `gt_tbl` | `il_compare(spec, ...)` always returns `il_spec` |
| gt | `fmt_number(columns = c(x, y))` tidyselect | `il_compare(c(first_name, last_name), ...)` tidyselect |
| gt | `cells_body()` targets locations | `block_on()` targets blocking conditions |
| gt | `cell_text()` / `cell_fill()` spec helpers | `cl_exact()` / `cl_jaro_winkler()` spec helpers |

### 3.2 `il_compare()`

```r
il_compare(spec, col, method, ...)
```

| Argument | Type | Description |
|----------|------|-------------|
| `spec` | `il_spec` | The specification to modify (piped in) |
| `col` | tidyselect | Column(s) to compare; supports bare names, `c()`, and tidyselect helpers |
| `method` | comparison helper | A `cl_*()` object describing the comparison |
| `...` | | Reserved for future use |

`col` accepts tidyselect expressions, following gt's `columns` convention.
A single bare name targets one column; `c(first_name, last_name)` applies
the same comparison method to both columns, and `starts_with("addr_")`
applies it to every matching column. Each targeted column gets its own
comparison layer in the spec.

```r
# These are equivalent:
spec |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(last_name,  cl_jaro_winkler(0.9, 0.7))

spec |>
  il_compare(c(first_name, last_name), cl_jaro_winkler(0.9, 0.7))
```

This mirrors gt's `fmt_number(columns = c(price, cost), ...)` pattern.

Returns: the updated `il_spec` (a new copy, not a mutation).

### 3.3 `il_block_on()`

```r
il_block_on(spec, ..., .where = NULL)
```

| Argument | Type | Description |
|----------|------|-------------|
| `spec` | `il_spec` | The specification to modify |
| `...` | unquoted names | Columns for equality blocking (AND-ed) |
| `.where` | character or NULL | Optional raw SQL for non-equality conditions |

Multiple `il_block_on()` calls add rules that are OR-ed together, just as
multiple `block_on()` entries are OR-ed in splink. Within a single call,
columns are AND-ed.

```r
# "Block where state matches, OR where first name matches"
spec |>
  il_block_on(state) |>
  il_block_on(first_name)

# "Block where state AND year both match"
spec |>
  il_block_on(state, year)
```

This mirrors dplyr's `join_by()`, where multiple conditions inside one
call are AND-ed and you use separate joins for OR logic.

---

## 4 Comparison Helpers (`cl_*`)

Comparison helpers are small constructors prefixed with `cl_` (comparison
level). The prefix follows ggplot2's convention of grouping related
constructors under a shared prefix (`geom_`, `scale_`, `stat_`).

### 4.1 Similarity Functions

Each creates a multi-level comparison with sensible defaults: a null
level, an exact-match level, threshold levels, and an else level.

| Function | Column type | Example |
|----------|-------------|---------|
| `cl_exact()` | Any | `il_compare(city, cl_exact())` |
| `cl_jaro_winkler(...)` | String | `il_compare(name, cl_jaro_winkler(0.9, 0.7))` |
| `cl_jaro(...)` | String | `il_compare(name, cl_jaro(0.9))` |
| `cl_levenshtein(...)` | String | `il_compare(name, cl_levenshtein(1, 2))` |
| `cl_damerau_levenshtein(...)` | String | `il_compare(name, cl_damerau_levenshtein(1))` |
| `cl_jaccard(...)` | String | `il_compare(name, cl_jaccard(0.9))` |
| `cl_cosine(...)` | Numeric/vector | `il_compare(vec, cl_cosine(0.8))` |
| `cl_date_diff(...)` | Date | `il_compare(dob, cl_date_diff(days(30), days(365)))` |
| `cl_distance_km(...)` | Lat/lon pair | `il_compare(lat, lon, cl_distance_km(km(5), km(50)))` |
| `cl_numeric_diff(...)` | Numeric | `il_compare(age, cl_numeric_diff(1, 5))` |
| `cl_pct_diff(...)` | Numeric | `il_compare(income, cl_pct_diff(0.05, 0.2))` |
| `cl_array_intersect(...)` | Array/list | `il_compare(tags, cl_array_intersect(2, 1))` |
| `cl_custom(...)` | Any | `il_compare(x, cl_custom("l.x + r.x > 10"))` |

Thresholds are passed as unnamed arguments in order from strictest to
most lenient — the same direction you read them in a waterfall chart.

### 4.2 Domain Comparisons

Pre-built multi-column comparisons that encode domain knowledge, like
recipes `step_*` functions that bundle common preprocessing.

| Function | Description |
|----------|-------------|
| `cl_name()` | Exact + Jaro-Winkler + Jaro levels tuned for personal names |
| `cl_dob()` | Date-of-birth comparison with string-parsing, date-diff, and component matching |
| `cl_email()` | Email comparison: exact, username, domain |
| `cl_forename_surname()` | Forename + surname with cross-field swap detection |
| `cl_postcode()` | Postcode comparison with optional geographic fallback |

### 4.3 Unit Helpers

gt provides `px()`, `pct()`, and `md()` — small tagged-value constructors
that make function calls self-documenting and type-safe. irelink follows
this pattern for threshold arguments that carry physical or temporal units.

| Helper | Returns | Example |
|--------|---------|---------|
| `days(n)` | A duration in days | `cl_date_diff(days(30), days(365))` |
| `months(n)` | A duration in months | `cl_date_diff(months(1), months(12))` |
| `years(n)` | A duration in years | `cl_date_diff(years(1))` |
| `km(n)` | A distance in kilometres | `cl_distance_km(km(5), km(50))` |
| `mi(n)` | A distance in miles | `cl_distance_km(mi(3), mi(30))` |

These are intentionally tiny: each creates a one-element list with a class
tag (e.g., `il_days`). The `cl_*()` helper reads the tag and converts to
the appropriate SQL expression.

```r
# Without helpers — ambiguous units, fragile
il_compare(dob, cl_date_diff(30, 365))

# With helpers — self-documenting, unit-safe
il_compare(dob, cl_date_diff(days(30), days(365)))

# Mix units freely — converted internally
il_compare(dob, cl_date_diff(months(1), years(1)))
```

The unit helpers are optional: bare numerics still work for callers who
prefer brevity. But when a function accepts multiple threshold arguments,
the helpers prevent mistakes like passing months where days are expected.
This mirrors how gt's `px(12)` makes clear what `12` means.

### 4.4 Composing Custom Levels

When the built-in comparisons do not fit, users build levels from
scratch. This is the equivalent of writing a custom ggplot `stat_*()`.

```r
il_compare(
  name,
  cl_levels(
    cl_null(),
    cl_exact(term_frequency = TRUE),
    cl_jaro_winkler(0.95),
    cl_jaro_winkler(0.88),
    cl_else()
  )
)
```

Level composition operators mirror comparison-level composition in splink:

```r
# AND: both conditions must hold
cl_and(cl_exact(first_name), cl_exact(surname))

# OR: either condition holds
cl_or(cl_jaro_winkler(name, 0.9), cl_levenshtein(name, 1))

# NOT: negate a condition
cl_not(cl_exact(name))
```

---

## 5 Model Creation and Training

### 5.1 `il_model()`

Bind a spec to data and a database connection.

```r
il_model(.data, ..., spec, con, link_type = c("dedupe", "link", "link_and_dedupe"))
```

| Argument | Type | Description |
|----------|------|-------------|
| `.data` | data frame | First (or only) input dataset |
| `...` | data frames | Additional datasets for linkage |
| `spec` | `il_spec` | The comparison + blocking specification |
| `con` | DBI connection | Database backend (DuckDB, SQLite, Postgres, ...) |
| `link_type` | character | One of `"dedupe"`, `"link"`, or `"link_and_dedupe"` |

```r
# Deduplication: one dataset
model <- il_model(voters, spec = spec, con = con)

# Linkage: two datasets
model <- il_model(voters_2020, voters_2024, spec = spec, con = con, link_type = "link")
```

**Comparison to dbplyr:** just as `dplyr::tbl(con, "flights")` binds a
connection to a table name and returns a lazy reference, `il_model()`
binds a connection to data + spec and returns a model object ready for
training.

### 5.2 Database Connections

irelink uses DBI connections — the same ones dbplyr users already create.
No new connection API to learn.

```r
# DuckDB — fast local default (equivalent to splink's DuckDBAPI())
con <- DBI::dbConnect(duckdb::duckdb())

# SQLite — lightweight alternative
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

# PostgreSQL — production scale
con <- DBI::dbConnect(RPostgres::Postgres(), dbname = "linkage")

# Spark — distributed computing
con <- sparklyr::spark_connect(master = "local")
```

**Comparison to dbplyr:**

```r
# dbplyr pattern:
con <- DBI::dbConnect(duckdb::duckdb())
tbl(con, "flights") |> filter(dep_delay > 60) |> collect()

# irelink pattern:
con <- DBI::dbConnect(duckdb::duckdb())
il_model(df, spec = spec, con = con) |> il_estimate_u() |> predict()
```

Same connection, same pattern, different verb vocabulary.

### 5.3 Training Verbs

Training functions are pipe-friendly verbs. Each takes a model, does
work, and returns an updated model — like dplyr verbs that take a tibble
and return a tibble.

```r
model <- il_model(df, spec = spec, con = con) |>
  il_estimate_prior(block_on(first_name, surname), recall = 0.7) |>
  il_estimate_u(max_pairs = 1e6) |>
  il_estimate_em(block_on(first_name)) |>
  il_estimate_em(block_on(dob))
```

| Verb | What it does | splink equivalent |
|------|-------------|-------------------|
| `il_estimate_prior()` | Estimate the probability that two random records match, using deterministic rules and a recall assumption | `linker.training.estimate_probability_two_random_records_match()` |
| `il_estimate_u()` | Estimate non-match (u) probabilities by randomly sampling record pairs | `linker.training.estimate_u_using_random_sampling()` |
| `il_estimate_em()` | Run the EM algorithm under a blocking rule to learn m and/or u parameters | `linker.training.estimate_parameters_using_expectation_maximisation()` |
| `il_estimate_m_from_labels()` | Learn match (m) probabilities from labelled data | `linker.training.estimate_m_from_pairwise_labels()` |

The blocking rules passed to training are distinct from the prediction
blocking in the spec. `block_on()` (without the `il_` prefix) creates
these training-time blocking specifications:

```r
# block_on() for training — analogous to join_by() in dplyr
il_estimate_em(model, block_on(first_name, surname))
```

**Comparison to tidymodels:** training mirrors `fit()` from parsnip.
A tidymodels user writes `fit(workflow, data = df)` and gets back a
fitted workflow; an irelink user writes `il_estimate_em(model, ...)` and
gets back a trained model.

### 5.4 Standard Generics on Models

```r
print(model)
#> ── irelink model ──
#> Type:   dedupe
#> Data:   voters (5,000 rows)
#> Status: trained (3 training rounds)
#> Comparisons: first_name (jaro_winkler), surname (jaro_winkler),
#>              dob (date_diff), city (exact), email (email)
#> Blocking:    first_name | surname

summary(model)
#> ── Model parameters ──
#> Prior: P(match) = 0.00032
#>
#>  comparison            level          m       u     weight
#>  first_name   Exact match       0.893   0.005     7.48
#>  first_name   JW ≥ 0.9          0.072   0.009     3.00
#>  first_name   JW ≥ 0.7          0.018   0.042    -1.22
#>  first_name   All other         0.017   0.944    -5.79
#>  ...
```

---

## 6 Prediction

### 6.1 `predict()`

`predict()` is an S3 method — users call the same generic they use for
`lm`, `glm`, or any model object.

```r
predict(model, threshold = 0.85, type = c("pairs", "weights"))
```

| Argument | Type | Description |
|----------|------|-------------|
| `model` | `il_model` | A trained model |
| `threshold` | numeric (0–1) | Minimum match probability to return |
| `type` | character | `"pairs"` (default) returns scored pairs; `"weights"` returns match weights on log₂ scale |

Returns: a tibble (class `il_compared`) with one row per candidate pair.

```r
pairs <- predict(model, threshold = 0.85)
pairs
#> # A tibble: 1,247 × 10
#>    id_l  id_r  match_weight match_prob gamma_first_name gamma_surname
#>    <chr> <chr>        <dbl>      <dbl>            <int>         <int>
#>  1 0042  0197         12.3       0.998                2             2
#>  2 0003  0891          8.7       0.996                2             1
#>  3 0156  0312          5.2       0.973                1             2
#>  4 0088  0445          3.1       0.896                1             1
#>  # ℹ 1,243 more rows
#>  # ℹ 4 more variables: gamma_dob <int>, gamma_city <int>, ...
```

The output is a tibble. Pipe it into dplyr, ggplot2, or anything else:

```r
# Filter to high-confidence matches
pairs |> filter(match_prob > 0.99)

# Histogram of match weights
pairs |>
  ggplot(aes(x = match_weight)) +
  geom_histogram(binwidth = 1, fill = "steelblue")
```

**Comparison to dplyr joins:**

```r
# dplyr: deterministic join (returns a tibble)
inner_join(df_a, df_b, by = join_by(id))

# irelink: probabilistic linkage (returns a tibble)
predict(model, threshold = 0.85)
```

Both return tibbles. The difference is that irelink's tibble contains
match probabilities instead of deterministic equalities.

### 6.2 Lightweight Real-Time Matching

For one-off comparisons without a full training pipeline:

```r
il_compare_records(record_a, record_b, spec = spec, con = con)
```

And for finding matches to new records in an already-trained model:

```r
il_find_matches(model, new_records, threshold = 0.85)
```

---

## 7 Clustering

### 7.1 `il_cluster()`

Groups scored pairs into entity clusters using connected components.

```r
il_cluster(pairs, threshold = NULL, method = c("connected", "best_link"))
```

| Argument | Type | Description |
|----------|------|-------------|
| `pairs` | `il_compared` (tibble) | Scored record pairs from `predict()` |
| `threshold` | numeric or NULL | Optional secondary threshold (if different from the prediction threshold) |
| `method` | character | `"connected"` (default) or `"best_link"` for single-best-link clustering |

Returns: a tibble with one row per input record.

```r
clusters <- pairs |> il_cluster()
clusters
#> # A tibble: 5,000 × 8
#>    cluster_id record_id first_name surname dob        city    email
#>         <int> <chr>     <chr>      <chr>   <date>     <chr>   <chr>
#>  1          1 0042      John       Smith   1985-01-15 London  john@x.com
#>  2          1 0197      Jon        Smith   1985-02-15 London  j.smith@x.com
#>  3          2 0003      Jane       Brown   1990-03-20 Oxford  jane@y.com
#>  4          2 0891      Jane       Browne  1990-04-20 Oxford  jane.b@y.com
#>  # ℹ 4,996 more rows
```

**Comparison to dplyr's `group_by()`:** just as `group_by()` assigns
group labels to rows, `il_cluster()` assigns cluster IDs. Records with
the same `cluster_id` are the same entity.

```r
# dplyr: group rows by a known column
df |> group_by(department) |> summarise(n = n())

# irelink: group rows by discovered entity
pairs |> il_cluster() |> count(cluster_id, sort = TRUE)
```

### 7.2 Graph Metrics

```r
il_graph_metrics(pairs, clusters)
#> $nodes
#> # A tibble: 5,000 × 4
#>   record_id cluster_id degree centrality
#>
#> $edges
#> # A tibble: 1,247 × 5
#>   id_l  id_r  match_prob cluster_id is_bridge
#>
#> $clusters
#> # A tibble: 3,210 × 4
#>   cluster_id size  density centralization
```

Returns a named list of tibbles — easy to pull apart with `$` or
`purrr::pluck()`.

---

## 8 Visualization and ggplot2 Integration

irelink's visualization strategy: **produce tidy data, let ggplot2 do the
rendering.**

### 8.1 Data-Extraction Functions

Every chart in splink has an irelink equivalent that returns a tibble of
chart-ready data. Users can pass this directly to `ggplot()`.

| Function | Returns | Use with |
|----------|---------|----------|
| `il_weights(model)` | Tibble of comparison levels with match weights | `geom_col()` |
| `il_parameters(model)` | Tibble of m and u values per level | `geom_point()` |
| `il_waterfall(pairs, row)` | Tibble of weight contributions for one pair | `geom_col()` |
| `il_roc(model, labels)` | Tibble of FPR and TPR at each threshold | `geom_line()` |
| `il_precision_recall(model, labels)` | Tibble of precision and recall | `geom_line()` |
| `il_training_history(model)` | Tibble of parameter values per EM iteration | `geom_line()` + `facet_wrap()` |

### 8.2 Convenience Plots via `autoplot()`

For quick inspection, `autoplot()` (from ggplot2) returns a ready-made
plot. This is the same pattern used by the `forecast`, `survival`, and
`broom` packages.

```r
# Quick match-weights chart
autoplot(model)

# Quick match-weight histogram
autoplot(pairs)

# Quick waterfall for one pair
autoplot(pairs, which = 1)
```

### 8.3 Full ggplot2 Examples

#### Match Weights by Comparison

```r
il_weights(model) |>
  ggplot(aes(x = level, y = log2_bayes_factor, fill = direction)) +
  geom_col() +
  facet_wrap(~ comparison, scales = "free_x") +
  scale_fill_manual(values = c(match = "#2a9d8f", non_match = "#e76f51")) +
  labs(
    title = "Match Weights by Comparison Level",
    x = "Comparison level",
    y = "Match weight (log\u2082 Bayes factor)"
  ) +
  coord_flip() +
  theme_minimal()
```

The data behind this chart:

```r
il_weights(model)
#> # A tibble: 16 × 5
#>    comparison   level            m_prob  u_prob log2_bayes_factor
#>    <chr>        <chr>             <dbl>   <dbl>             <dbl>
#>  1 first_name   Exact match      0.893   0.005              7.48
#>  2 first_name   JW >= 0.9        0.072   0.009              3.00
#>  3 first_name   JW >= 0.7        0.018   0.042             -1.22
#>  4 first_name   All other        0.017   0.944             -5.79
#>  5 surname      Exact match      0.875   0.003              8.19
#>  ...
```

#### Match Weight Histogram

```r
pairs |>
  ggplot(aes(x = match_weight)) +
  geom_histogram(binwidth = 1, fill = "steelblue", color = "white") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  labs(
    title = "Distribution of Match Weights",
    x = "Match weight",
    y = "Count"
  ) +
  theme_minimal()
```

#### Waterfall Chart for a Single Pair

```r
il_waterfall(pairs, which = 1) |>
  ggplot(aes(x = reorder(step, order), y = contribution, fill = direction)) +
  geom_col() +
  coord_flip() +
  scale_fill_manual(values = c(positive = "#2a9d8f", negative = "#e76f51",
                                prior = "#264653", final = "#264653")) +
  labs(
    title = "Match Weight Decomposition",
    x = NULL,
    y = "Contribution to match weight"
  ) +
  theme_minimal()
```

#### ROC Curve

```r
il_roc(model, labels = labelled_pairs) |>
  ggplot(aes(x = fpr, y = tpr)) +
  geom_line(color = "#2a9d8f", linewidth = 1) +
  geom_abline(linetype = "dashed", color = "grey60") +
  labs(
    title = "ROC Curve",
    x = "False Positive Rate",
    y = "True Positive Rate"
  ) +
  coord_equal() +
  theme_minimal()
```

#### EM Training Convergence

```r
il_training_history(model) |>
  ggplot(aes(x = iteration, y = value, color = level)) +
  geom_line() +
  facet_wrap(~ comparison, scales = "free_y") +
  labs(
    title = "Parameter Convergence Across EM Iterations",
    x = "Iteration",
    y = "Parameter estimate"
  ) +
  theme_minimal()
```

### 8.4 Why This Approach

splink renders charts by injecting data into bundled Vega-Lite JSON
templates. This is effective in Jupyter notebooks but foreign to R users.

irelink instead follows the ggplot2 ecosystem pattern:

| splink approach | irelink approach | Advantage |
|-----------------|-----------------|-----------|
| `linker.visualisations.match_weights_chart()` → Vega-Lite JSON | `il_weights(model) \|> ggplot(...)` | Users control every aesthetic |
| Fixed chart templates | Tidy data + ggplot grammar | Infinite customization |
| `save_offline_chart(chart, "out.html")` | `ggsave("out.png")` | Familiar export path |
| Interactive via Altair | Interactive via plotly::ggplotly() | One-line interactivity |

---

## 9 Exploratory Analysis

Pre-model functions for understanding data quality, also returning
tibbles.

```r
# Column completeness across one or more tables
il_completeness(voters_2020, voters_2024, con = con) |>
  ggplot(aes(x = column, y = pct_non_null, fill = table)) +
  geom_col(position = "dodge") +
  coord_flip()

# Column profiling (value distributions)
il_profile(voters_2020, first_name, surname, dob, con = con)

# Blocking analysis: how many pairs does each rule produce?
il_count_pairs(
  voters_2020, voters_2024,
  block_on(state),
  block_on(first_name),
  con = con,
  link_type = "link"
)
#> # A tibble: 2 × 4
#>   rule              pairs_generated cumulative_pairs pct_of_cartesian
#>   <chr>                       <dbl>            <dbl>            <dbl>
#> 1 block_on(state)           245000           245000             1.23
#> 2 block_on(first_name)      182000           389000             1.95

# String similarity exploration (no database needed)
il_string_similarity("John", "Jon")
#> # A tibble: 1 × 5
#>   jaro  jaro_winkler levenshtein damerau_levenshtein jaccard
#>   <dbl>        <dbl>       <int>               <int>   <dbl>
#> 1 0.933        0.953           1                   1   0.667
```

---

## 10 Evaluation

```r
# Prediction errors against labelled pairs
il_errors(model, labels = labelled_pairs, threshold = 0.85)
#> # A tibble: 47 × 6
#>    id_l  id_r  match_weight match_prob true_label error_type
#>    <chr> <chr>        <dbl>      <dbl> <lgl>      <chr>
#>  1 0042  0312         -2.3       0.17  TRUE       false_negative
#>  2 0088  0445          5.1       0.97  FALSE      false_positive
#>  ...

# Accuracy summary
il_accuracy(model, labels = labelled_pairs)
#> # A tibble: 50 × 7
#>    threshold precision recall    f1   tp    fp    fn
#>        <dbl>     <dbl>  <dbl> <dbl> <int> <int> <int>
#>  1      0.50     0.891  0.967 0.927   580    70    20
#>  2      0.55     0.903  0.962 0.932   577    62    23
#>  ...
```

---

## 11 End-to-End Worked Examples

### 11.1 Deduplication — Minimal

```r
library(irelink)
library(dplyr)

con <- DBI::dbConnect(duckdb::duckdb())

il_demo("fake_1000") |>
  il_model(
    spec = il_spec() |>
      il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
      il_compare(surname,    cl_jaro_winkler(0.9, 0.7)) |>
      il_compare(dob,        cl_date_diff(days(30), days(365))) |>
      il_compare(city,       cl_exact()) |>
      il_compare(email,      cl_email()) |>
      il_block_on(first_name) |>
      il_block_on(surname),
    con = con
  ) |>
  il_estimate_u() |>
  il_estimate_em(block_on(first_name, surname)) |>
  predict(threshold = 0.95) |>
  il_cluster()
```

### 11.2 Two-Table Linkage with Exploration

```r
library(irelink)
library(dplyr)
library(ggplot2)

con <- DBI::dbConnect(duckdb::duckdb())

# ── Explore data quality ──
il_completeness(voters_2020, voters_2024, con = con) |>
  ggplot(aes(x = column, y = pct_non_null, fill = table)) +
  geom_col(position = "dodge") +
  coord_flip() +
  theme_minimal()

# ── Define comparisons ──
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(last_name,  cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob,        cl_date_diff(days(30), days(365))) |>
  il_compare(county,     cl_exact(term_frequency = TRUE)) |>
  il_block_on(last_name) |>
  il_block_on(first_name, county)

# ── Check blocking coverage ──
il_count_pairs(
  voters_2020, voters_2024,
  block_on(last_name),
  block_on(first_name, county),
  con = con,
  link_type = "link"
)

# ── Train ──
model <- il_model(
  voters_2020, voters_2024,
  spec = spec, con = con, link_type = "link"
) |>
  il_estimate_prior(block_on(first_name, last_name, dob), recall = 0.7) |>
  il_estimate_u(max_pairs = 1e6) |>
  il_estimate_em(block_on(first_name, last_name)) |>
  il_estimate_em(block_on(dob))

# ── Inspect model ──
summary(model)
autoplot(model)  # match-weights chart

il_training_history(model) |>
  ggplot(aes(x = iteration, y = value, color = level)) +
  geom_line() +
  facet_wrap(~ comparison, scales = "free_y") +
  theme_minimal()

# ── Predict ──
pairs <- predict(model, threshold = 0.85)

pairs |>
  ggplot(aes(x = match_weight)) +
  geom_histogram(binwidth = 1, fill = "steelblue") +
  theme_minimal()

# ── Cluster ──
clusters <- pairs |> il_cluster()

# ── Downstream analysis in dplyr ──
# How many matched entities span both datasets?
clusters |>
  group_by(cluster_id) |>
  summarise(
    n_records    = n(),
    n_datasets   = n_distinct(source_dataset),
    states       = paste(unique(state), collapse = ", ")
  ) |>
  filter(n_records > 1)
```

### 11.3 Joining Linked Results Back to Source Data

One of the most natural things a dplyr user will do after linkage is join
cluster assignments back to the original data and analyze across sources.

```r
# Join clusters back to both original tables
matched_voters <- voters_2020 |>
  left_join(
    clusters |> filter(source_dataset == "voters_2020"),
    by = c("id" = "record_id")
  ) |>
  left_join(
    clusters |> filter(source_dataset == "voters_2024") |>
      select(cluster_id, id_2024 = record_id),
    by = "cluster_id"
  )

# Compare a column across linked records
matched_voters |>
  filter(!is.na(cluster_id)) |>
  left_join(
    voters_2024 |> select(id, county_2024 = county),
    by = c("id_2024" = "id")
  ) |>
  count(county, county_2024) |>
  ggplot(aes(x = county, y = county_2024, fill = n)) +
  geom_tile() +
  scale_fill_viridis_c() +
  labs(title = "County Migration Between 2020 and 2024") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
```

### 11.4 Quick Comparison of Two Records

```r
il_compare_records(
  list(first_name = "John", surname = "Smith", dob = "1985-01-15"),
  list(first_name = "Jon",  surname = "Smith", dob = "1985-02-15"),
  spec = spec,
  con = con
)
#> # A tibble: 1 × 6
#>   match_weight match_prob gamma_first_name gamma_surname gamma_dob
#>          <dbl>      <dbl>            <int>         <int>     <int>
#> 1         8.73      0.996                1             2         1
```

---

## 12 Full API Reference Summary

### 12.1 Specification

| Function | Purpose |
|----------|---------|
| `il_spec()` | Create an empty linkage specification |
| `il_compare(spec, col, method)` | Add a comparison layer |
| `il_block_on(spec, ...)` | Add a prediction blocking rule |
| `block_on(...)` | Create a blocking rule for training (not part of spec) |

### 12.2 Comparison Helpers

| Function | Category |
|----------|----------|
| `cl_exact()` | Equality |
| `cl_jaro_winkler()`, `cl_jaro()`, `cl_jaccard()`, `cl_cosine()` | Similarity scores |
| `cl_levenshtein()`, `cl_damerau_levenshtein()` | Edit distance |
| `cl_date_diff()` | Temporal |
| `cl_distance_km()` | Geographic |
| `cl_numeric_diff()`, `cl_pct_diff()` | Numeric |
| `cl_array_intersect()` | Arrays |
| `cl_custom()` | Arbitrary SQL |
| `cl_name()`, `cl_dob()`, `cl_email()`, `cl_postcode()`, `cl_forename_surname()` | Domain bundles |
| `cl_levels()`, `cl_null()`, `cl_else()`, `cl_and()`, `cl_or()`, `cl_not()` | Level composition |

### 12.3 Model

| Function | Purpose |
|----------|---------|
| `il_model(.data, ..., spec, con)` | Bind data + spec + connection |
| `il_estimate_prior(model, ..., recall)` | Estimate global match probability |
| `il_estimate_u(model, max_pairs)` | Estimate u parameters from random sampling |
| `il_estimate_em(model, block_on(...))` | Train m/u via EM |
| `il_estimate_m_from_labels(model, labels)` | Train m from labelled data |
| `predict(model, threshold)` | Score all blocked pairs (S3 generic) |
| `print(model)`, `summary(model)`, `autoplot(model)` | Inspect model (S3 generics) |
| `il_save(model, path)` / `il_load(path)` | Serialize / deserialize |

### 12.4 Post-Prediction

| Function | Purpose |
|----------|---------|
| `il_cluster(pairs, threshold, method)` | Cluster into entities |
| `il_graph_metrics(pairs, clusters)` | Node, edge, and cluster metrics |
| `il_find_matches(model, new_records, threshold)` | Match new records against trained data |
| `il_compare_records(record_a, record_b, spec, con)` | Score two specific records |

### 12.5 Exploration and Evaluation

| Function | Purpose |
|----------|---------|
| `il_completeness(...)` | Column completeness chart data |
| `il_profile(data, ..., con)` | Column value distributions |
| `il_count_pairs(data, ..., con)` | Blocking analysis: pair counts |
| `il_string_similarity(a, b)` | String similarity scores (no database) |
| `il_accuracy(model, labels)` | Accuracy table across thresholds |
| `il_errors(model, labels, threshold)` | False positives and negatives |

### 12.6 Visualization Data

| Function | Returns | Suggested geom |
|----------|---------|----------------|
| `il_weights(model)` | Level weights | `geom_col()` + `facet_wrap()` |
| `il_parameters(model)` | m/u values | `geom_point()` |
| `il_waterfall(pairs, which)` | Weight decomposition | `geom_col()` + `coord_flip()` |
| `il_roc(model, labels)` | ROC curve data | `geom_line()` |
| `il_precision_recall(model, labels)` | PR curve data | `geom_line()` |
| `il_training_history(model)` | EM convergence traces | `geom_line()` + `facet_wrap()` |

---

## 13 Design Decision Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Class system | S3 | Simpler; idiomatic R; pipe-friendly without reference semantics; trained state stored as list elements (like a fitted lm) |
| Object mutation | Functional (copy-on-modify) | Each training verb returns a new object; no side effects; matches dplyr convention |
| Prefix convention | `il_` for verbs, `cl_` for comparison helpers | Mirrors ggplot2's `geom_`/`scale_`/`stat_` and gt's `tab_`/`fmt_`/`cols_` prefix grouping |
| Pipe operator | `\|>` (no `+`) | Follows gt's modern convention; works natively in R >= 4.1 |
| Unit helpers | `days()`, `km()`, `mi()`, etc. | Self-documenting thresholds; mirrors gt's `px()`, `pct()` pattern |
| Column selection | Tidyselect (`tidyselect` / `rlang`) | Bare names, `c()`, and select helpers; matches gt's `columns` convention and dplyr everywhere |
| Database interface | DBI connections | Users already know `DBI::dbConnect()`; no new connection API; identical to dbplyr |
| SQL generation | dbplyr + glue for template assembly | Leverage existing dialect translations; inject backend-specific functions via `sql()` |
| Visualization | Tidy data + ggplot2 | No custom chart library; users control every aesthetic; `autoplot()` for convenience |
| Predictions and clusters | Plain tibbles | Flow into dplyr, ggplot2, readr, and everything else without conversion |

---

## 14 Lessons from gt

This section documents specific patterns adopted from or influenced by
the gt package (Posit's table-formatting library, 200+ exports). gt
represents Posit's most modern API design and validates several irelink
decisions while inspiring new ones.

### 14.1 Pure Pipe Chains

gt abandoned the `+` operator used by ggplot2 and instead chains every
call with `|>`. Every `tab_*()`, `fmt_*()`, and `cols_*()` function
takes a `gt_tbl` as its first argument and returns a `gt_tbl`:

```r
# gt
gt(data) |>
  tab_header(title = "Sales") |>
  fmt_number(columns = price, decimals = 0) |>
  cols_label(price = "Price (USD)")

# irelink — same pattern
il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9)) |>
  il_compare(dob, cl_date_diff(days(30))) |>
  il_block_on(state)
```

This was already the irelink design, but gt's success at scale (200+ functions
chained with `|>`) confirms it works for large APIs without confusion.

### 14.2 Prefix Families

gt organises its 200+ exports into systematic prefix groups:

| Prefix | Count | Purpose |
|--------|-------|---------|
| `fmt_` | 32 | Format cell values |
| `vec_` | 18 | Vectorised formatting (non-table) |
| `cols_` | 17 | Column operations |
| `opt_` | 14 | Global options |
| `cells_` | 14 | Location targeting |
| `tab_` | 13 | Table structure |
| `cell_` | 6 | Style specifications |

irelink follows the same strategy with fewer groups:

| Prefix | Purpose | gt analogy |
|--------|---------|------------|
| `il_` | Core verbs (spec, model, prediction, clustering) | `tab_` + `fmt_` |
| `cl_` | Comparison-level helpers (method specification) | `cells_` + `cell_` |
| (none) | Unit helpers (`days()`, `km()`, `mi()`) | `px()`, `pct()` |

The `il_` prefix is larger than any single gt prefix because irelink has
fewer total exports. If the API grows, we can carve out sub-prefixes
(e.g., `il_eval_*()` for evaluation functions) without breaking changes.

### 14.3 Specification vs. Location Separation

gt's `tab_style()` cleanly separates **what** to apply from **where**:

```r
tab_style(
  data,
  style     = cell_text(weight = "bold"),     # WHAT
  locations = cells_body(columns = price)     # WHERE
)
```

irelink's `il_compare()` follows the same separation:

```r
il_compare(
  spec,
  col    = first_name,              # WHERE (which column)
  method = cl_jaro_winkler(0.9)     # WHAT (comparison method)
)
```

And `cl_levels()` composes method layers just as `list(cell_text(...),
cell_fill(...))` composes style layers:

```r
il_compare(
  spec,
  col    = name,
  method = cl_levels(
    cl_exact(),
    cl_jaro_winkler(0.95),
    cl_else()
  )
)
```

### 14.4 Tidyselect for All Column Arguments

gt accepts tidyselect everywhere a `columns` argument appears:

```r
fmt_number(data, columns = c(price, cost), decimals = 2)
fmt_number(data, columns = starts_with("amt_"), decimals = 0)
fmt_number(data, columns = where(is.numeric), decimals = 2)
```

irelink adopts this for `il_compare()`:

```r
il_compare(spec, c(first_name, last_name), cl_jaro_winkler(0.9))
il_compare(spec, starts_with("addr_"), cl_levenshtein(2))
```

And for `il_block_on()`:

```r
il_block_on(spec, starts_with("geo_"))
```

This eliminates the need for loop-style column iteration that splink
often requires.

### 14.5 Tagged-Value Helpers

gt provides `px()`, `pct()`, `md()`, and `html()` — tiny functions that
create tagged values. These do nothing complex: `px(12)` returns a list
with class `"px"` and value `12`. Their purpose is self-documentation
and type safety.

irelink's unit helpers follow the same principle:

| gt helper | irelink helper | Purpose |
|-----------|---------------|---------|
| `px(12)` | `days(30)` | Tagged numeric with unit semantics |
| `pct(50)` | `km(5)` | Tagged numeric with unit semantics |
| `md("**bold**")` | `cl_custom("l.x + r.x")` | Tagged string with processing semantics |

### 14.6 Accumulation Without Replacement

In gt, repeated calls to the same verb accumulate rather than replace:

```r
gt(data) |>
  tab_footnote("Source A", locations = cells_body(columns = x)) |>
  tab_footnote("Source B", locations = cells_body(columns = y))
# Both footnotes appear
```

irelink follows the same rule:

```r
il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9)) |>
  il_compare(last_name,  cl_jaro_winkler(0.9))
# Both comparisons are registered

il_spec() |>
  il_block_on(state) |>
  il_block_on(first_name)
# Both blocking rules are registered (OR-ed)
```

This is a departure from option-setter APIs where the last call wins.
Every `il_compare()` and `il_block_on()` adds to the spec, never
overwrites. This matches both gt's accumulation and ggplot2's layer
stacking.

---

## Appendix: Tidyverse and gt Comparison Table

| Concept | Tidyverse / gt example | irelink equivalent |
|---------|----------------------|-------------------|
| Pipe chain | `df \|> filter() \|> mutate()` | `model \|> il_estimate_u() \|> il_estimate_em()` |
| Pure pipes (no `+`) | `gt(data) \|> tab_header() \|> fmt_number()` | `il_spec() \|> il_compare() \|> il_block_on()` |
| Specification helper | `aes(x = mpg, y = hp)` | `cl_jaro_winkler(0.9, 0.7)` |
| Location helper | `cells_body(columns = price)` | `il_block_on(state)` |
| Style spec helper | `cell_text(weight = "bold")` | `cl_exact(term_frequency = TRUE)` |
| Unit helper | `px(12)`, `pct(50)` | `days(30)`, `km(5)` |
| Tidyselect columns | `fmt_number(columns = c(x, y))` | `il_compare(c(first_name, last_name), ...)` |
| Layer accumulation | `ggplot() + geom_point() + geom_line()` | `il_spec() \|> il_compare(...) \|> il_compare(...)` |
| Accumulation (gt) | `tab_footnote(...) \|> tab_footnote(...)` | `il_block_on(...) \|> il_block_on(...)` |
| Join condition | `join_by(a == b)` | `il_block_on(first_name, surname)` |
| Lazy table reference | `tbl(con, "flights")` | `il_model(df, spec = spec, con = con)` |
| Model fitting | `fit(workflow, data)` | `il_estimate_em(model, block_on(...))` |
| Prediction | `predict(fit, newdata)` | `predict(model, threshold = 0.85)` |
| Group assignment | `group_by(department)` | `il_cluster(pairs)` |
| Plot convenience | `autoplot(decomposition)` | `autoplot(model)` |
| Tidy output | Every verb returns a tibble | Every irelink function returns a tibble (or S3 that pipes) |
| Database backend | `DBI::dbConnect(duckdb())` | `DBI::dbConnect(duckdb())` — identical |
