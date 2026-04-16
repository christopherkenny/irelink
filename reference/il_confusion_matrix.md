# Confusion Matrix at a Threshold

Computes the thresholded confusion-matrix counts for labelled pairs.
Uses the same SQL-first scoring path as
[`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md)
on supported backends, so labelled pairs do not need to be predicted and
collected in full before evaluation.

## Usage

``` r
il_confusion_matrix(model, labels = NULL, threshold = 0.85, labels_col = NULL)
```

## Arguments

- model:

  A trained `il_model` object.

- labels:

  A data frame of labelled pairs with a logical or integer match
  indicator. Required unless `labels_col` is provided.

- threshold:

  A numeric value between 0 and 1 for classifying pairs as matches.
  Defaults to `0.85`.

- labels_col:

  Optional string naming a column in the original data containing
  ground-truth cluster/entity IDs. When provided, pairwise labels are
  derived automatically via
  [`labels_from_column()`](http://christophertkenny.com/irelink/reference/labels_from_column.md).

## Value

A one-row tibble containing `threshold`, `tp`, `fp`, `fn`, `tn`,
`fn_blocking_miss`, `precision`, `recall`, and `f1`.

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
labels <- data.frame(
  unique_id_l = c(1L, 1L),
  unique_id_r = c(11L, 2L),
  is_match = c(1L, 0L)
)

il_confusion_matrix(model, labels = labels, threshold = 0.85)
#> # A tibble: 1 × 9
#>   threshold    tp    fp    fn    tn fn_blocking_miss precision recall    f1
#>       <dbl> <int> <int> <int> <int>            <int>     <dbl>  <dbl> <dbl>
#> 1      0.85     1     1     0     0                0       0.5      1 0.667
DBI::dbDisconnect(con, shutdown = TRUE)
```
