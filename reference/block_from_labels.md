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
labels <- data.frame(
  unique_id_l = fake_1000_labels$unique_id_l,
  unique_id_r = fake_1000_labels$unique_id_r,
  is_match = as.integer(fake_1000_labels$clerical_match_score >= 0.5)
)
block_from_labels(fake_1000, labels, con = con)
#> # A tibble: 6 × 3
#>   column     recall n_matches_caught
#>   <chr>       <dbl>            <int>
#> 1 cluster     0.673             1367
#> 2 dob         0.403              819
#> 3 city        0.390              792
#> 4 email       0.359              730
#> 5 surname     0.258              525
#> 6 first_name  0.242              492
DBI::dbDisconnect(con, shutdown = TRUE)
```
