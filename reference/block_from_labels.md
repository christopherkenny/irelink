# Derive Blocking Rules from Labeled Pairs

For each column, computes the fraction of true-match pairs that share
the same value (recall). Helps identify which columns make effective
blocking keys.

## Usage

``` r
block_from_labels(.data, labels, columns = NULL, con = NULL)
```

## Arguments

- .data:

  A data frame or character table name.

- labels:

  A data frame with `unique_id_l`, `unique_id_r`, and `is_match`.

- columns:

  Character vector of column names to evaluate. `NULL` for all non-ID
  columns.

- con:

  A DBI connection from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with columns `column`, `recall` (fraction of true matches caught), and
`n_matches_caught`.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
block_from_labels(fake_1000, fake_1000_labels, con = con)
#> Warning: Unknown or uninitialised column: `is_match`.
#> Error in labels[as.logical(labels$is_match), , drop = FALSE]: Can't subset rows with `as.logical(labels$is_match)`.
#> ✖ Logical subscript `as.logical(labels$is_match)` must be size 1 or 3176, not 0.
DBI::dbDisconnect(con, shutdown = TRUE)
```
