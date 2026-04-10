# Find Blocking Rules Below a Pair-Count Threshold

Searches for single-column (and optionally two-column) blocking rules
that keep the total number of candidate pairs below a given ceiling.

## Usage

``` r
il_find_blocking_below(
  .data,
  max_pairs,
  columns = NULL,
  con = NULL,
  link_type = c("dedupe", "link"),
  max_depth = 2L
)
```

## Arguments

- .data:

  A data frame, dbplyr `tbl_lazy`, or character table name.

- max_pairs:

  Maximum number of pairs allowed.

- columns:

  Character vector of column names. `NULL` for all.

- con:

  A DBI connection object.

- link_type:

  One of `"dedupe"` (default) or `"link"`.

- max_depth:

  Maximum depth of column combinations (default `2`).

## Value

A tibble of qualifying blocking rules, sorted by `n_pairs` ascending.
Empty tibble if no rules qualify.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
il_find_blocking_below(fake_1000, max_pairs = 100000, con = con)
#> # A tibble: 21 × 6
#>    rule                 n_distinct coverage n_pairs pct_of_cartesian score
#>    <chr>                     <int>    <dbl>   <int>            <dbl> <dbl>
#>  1 first_name & email          507    0.801     539            0.108 0.800
#>  2 surname & email             506    0.819     594            0.119 0.818
#>  3 first_name & surname        502    0.831     608            0.122 0.83 
#>  4 first_name & dob            582    0.9       617            0.124 0.899
#>  5 first_name & city           511    0.802     634            0.127 0.801
#>  6 surname & dob               571    0.923     712            0.142 0.922
#>  7 surname & city              489    0.819     809            0.162 0.818
#>  8 city & email                418    0.787     901            0.180 0.786
#>  9 dob & email                 490    0.888     976            0.195 0.886
#> 10 dob & city                  501    0.891     977            0.196 0.889
#> # ℹ 11 more rows
DBI::dbDisconnect(con, shutdown = TRUE)
```
