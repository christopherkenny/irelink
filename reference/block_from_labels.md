# Derive Blocking Rules from Labelled Pairs

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

  A DBI connection.

## Value

A tibble with columns `column`, `recall` (fraction of true matches
caught), and `n_matches_caught`.

## Examples

``` r
if (FALSE) { # \dontrun{
block_from_labels(df, labels, con = con)
} # }
```
