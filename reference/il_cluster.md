# Cluster Scored Pairs into Entities

Groups scored record pairs into entity clusters using graph-based
methods. Analogous to
[`dplyr::group_by()`](https://dplyr.tidyverse.org/reference/group_by.html)
— just as `group_by()` assigns group labels, `il_cluster()` assigns
cluster IDs to records that represent the same real-world entity.

## Usage

``` r
il_cluster(
  pairs,
  threshold = NULL,
  method = c("connected", "best_link"),
  ties_method = c("lowest_id", "drop"),
  source_dataset = NULL
)
```

## Arguments

- pairs:

  An `il_compared` tibble from
  [`predict.il_model()`](http://christophertkenny.com/irelink/reference/predict.il_model.md).

- threshold:

  An optional secondary match-probability threshold. If `NULL` (the
  default), the threshold from prediction is used.

- method:

  One of `"connected"` (default) for connected-components clustering, or
  `"best_link"` for single-best-link clustering.

- ties_method:

  How to handle tied best-link probabilities when
  `method = "best_link"`. `"lowest_id"` (default) keeps the edge to the
  record with the smaller `unique_id`; `"drop"` removes all edges where
  the best-link probability is tied.

- source_dataset:

  An optional named character vector or data frame mapping `unique_id`
  values to their source dataset name. Used with `method = "best_link"`
  to enforce at-most-one-record per source dataset per cluster (splink's
  `duplicate_free_datasets` constraint). If a data frame, must contain
  columns `unique_id` and `source_dataset`.

## Value

A tibble with one row per input record, including a `cluster_id` column.

## Examples

``` r
df <- data.frame(
  unique_id = 1:20,
  first_name = c(
    'John', 'Jon', 'Jane', 'Jane', 'Bob',
    'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
    'John', 'Jon', 'Jane', 'Janet', 'Bob',
    'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
  ),
  surname = c(
    'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Brown', 'White', 'White',
    'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Browne', 'White', 'White'
  ),
  dob = c(
    '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
    '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
    '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
    '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
    '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
  ),
  city = c(
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
  ),
  email = c(
    'john@example.com', 'jon@example.com', 'jane@example.com',
    'jane@example.com', 'bob@example.com', 'bobby@example.com',
    'alice@example.com', 'alicia@example.com', 'tom@example.com',
    'thomas@example.com', 'john@example.com', 'jon@example.com',
    'jane@example.com', 'janet@example.com', 'bob@example.com',
    'robert@example.com', 'alice@example.com', 'alison@example.com',
    'tom@example.com', 'tomas@example.com'
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
#> EM trained: first_name and dob | skipped (blocked on): surname

pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)
DBI::dbDisconnect(con, shutdown = TRUE)
```
