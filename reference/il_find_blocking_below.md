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
if (FALSE) { # \dontrun{
con <- DBI::dbConnect(duckdb::duckdb())
il_find_blocking_below(df, max_pairs = 1000, con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
} # }
```
