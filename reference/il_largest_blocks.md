# Identify the Largest Blocking Bins

For a given blocking rule, returns the `n` blocking-key combinations
that produce the most record pairs. Useful for diagnosing skew — a
single dominant key can create a quadratic explosion of pairs.

## Usage

``` r
il_largest_blocks(
  .data,
  rule,
  n = 5L,
  con = NULL,
  link_type = c("dedupe", "link")
)
```

## Arguments

- .data:

  A data frame, dbplyr `tbl_lazy`, or character table name (first or
  only dataset).

- rule:

  A blocking rule created by
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md).

- n:

  Integer. Number of largest bins to return. Defaults to `5`.

- con:

  A DBI connection object. Optional when `.data` is a `tbl_lazy`.

- link_type:

  One of `"dedupe"` (default) or `"link"`.

## Value

A tibble with one row per blocking-key combination, sorted by descending
pair count. Columns are the blocking-key values plus `n_records` and
`n_pairs`.

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
  city = c(
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
il_largest_blocks(df, block_on(city), n = 3, con = con)
#> # A tibble: 3 × 3
#>   city   n_records n_pairs
#>   <chr>      <dbl>   <dbl>
#> 1 London         4       6
#> 2 Paris          4       6
#> 3 Berlin         4       6
DBI::dbDisconnect(con, shutdown = TRUE)
```
