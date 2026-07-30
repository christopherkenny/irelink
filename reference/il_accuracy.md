# Accuracy Metrics Across Thresholds

Computes a full suite of classification metrics at a range of
match-probability thresholds. Requires labeled pairs.

## Usage

``` r
il_accuracy(model, labels = NULL, labels_col = NULL)
```

## Arguments

- model:

  A trained `il_model` object.

- labels:

  A data frame of labeled pairs with a logical or integer match
  indicator. Required unless `labels_col` is provided.

- labels_col:

  Optional string naming a column in the original data containing
  ground-truth cluster/entity IDs. When provided, pairwise labels are
  derived automatically via
  [`labels_from_column()`](http://christophertkenny.com/irelink/reference/labels_from_column.md).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per threshold, containing columns `threshold`, `tp`, `fp`,
`fn`, `tn`, `fn_blocking_miss`, `precision`, `recall`, `f1`, `f2`,
`f0_5`, `specificity`, `npv`, `accuracy`, `p4`, and `phi`.

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
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpye6umx/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
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
labels <- data.frame(
  unique_id_l = c(1L, 1L),
  unique_id_r = c(11L, 2L),
  is_match = c(1L, 0L)
)

il_accuracy(model, labels = labels)
#> # A tibble: 3 × 16
#>   threshold    tp    fp    fn    tn fn_blocking_miss precision recall    f1
#>       <dbl> <int> <int> <int> <int>            <int>     <dbl>  <dbl> <dbl>
#> 1     0         1     1     0     0                0       0.5      1 0.667
#> 2     0.998     1     1     0     0                0       0.5      1 0.667
#> 3     1         0     0     1     1                0       1        0 0    
#> # ℹ 7 more variables: f2 <dbl>, f0_5 <dbl>, specificity <dbl>, npv <dbl>,
#> #   accuracy <dbl>, p4 <dbl>, phi <dbl>
DBI::dbDisconnect(con, shutdown = TRUE)
```
