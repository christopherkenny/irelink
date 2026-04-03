# Score Record Pairs from a Trained Model

Generates and scores all candidate record pairs that pass the blocking
rules, returning those above the match-probability threshold. This is an
S3 method for [`stats::predict()`](https://rdrr.io/r/stats/predict.html)
— the same generic used for `lm`, `glm`, and tidymodels objects.

## Usage

``` r
# S3 method for class 'il_model'
predict(
  object,
  threshold = 0.85,
  type = c("pairs", "weights"),
  collect = TRUE,
  include_fields = FALSE,
  ...
)
```

## Arguments

- object:

  A trained `il_model` object.

- threshold:

  A numeric value between 0 and 1. Only pairs with a match probability
  at or above this threshold are returned. Defaults to `0.85`.

- type:

  One of `"pairs"` (default) to return scored pairs, or `"weights"` to
  return match weights on a log-2 Bayes-factor scale.

- collect:

  If `TRUE` (the default), scored pairs are collected into an in-memory
  tibble. If `FALSE`, scoring is performed entirely in-database and the
  result is a lightweight `il_compared_lazy` reference that
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
  can consume directly — avoiding the round-trip of collecting millions
  of rows into R and re-uploading them. Requires a DuckDB or PostgreSQL
  backend.

- include_fields:

  If `TRUE`, the original column values from both records in each pair
  are included in the output (suffixed `_l` and `_r`). Defaults to
  `FALSE` for performance. When `collect = FALSE` the join is performed
  in-database before the table is created.

- ...:

  Additional arguments passed to the generic.

## Value

When `collect = TRUE`: an `il_compared` tibble with one row per
candidate pair, including columns for record IDs, match weight, match
probability, and per-comparison gamma values. When `collect = FALSE`: an
`il_compared_lazy` object referencing the scored pairs table in the
database.

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

pairs <- predict(model, threshold = 0.5)
DBI::dbDisconnect(con, shutdown = TRUE)
```
