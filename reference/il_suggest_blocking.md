# Suggest Blocking Rules

Enumerates single-column blocking rules and ranks them by a heuristic
that balances pair reduction against field coverage. Useful for choosing
initial blocking rules before training.

## Usage

``` r
il_suggest_blocking(
  .data,
  columns = NULL,
  con = NULL,
  link_type = c("dedupe", "link"),
  max_depth = 1L
)
```

## Arguments

- .data:

  A data frame, dbplyr `tbl_lazy`, or character table name.

- columns:

  Character vector of column names to evaluate. When `NULL` (the
  default), all non-ID columns are tried.

- con:

  A DBI connection object. Optional when `.data` is already registered
  in the database.

- link_type:

  One of `"dedupe"` (default) or `"link"`.

- max_depth:

  Maximum number of columns to combine in a single blocking rule.
  Defaults to `1` (single-column rules only). Set to `2` to also
  evaluate two-column combinations.

## Value

A tibble with columns `rule`, `n_distinct`, `coverage`, `n_pairs`,
`pct_of_cartesian`, and `score`, sorted by `score` descending. Higher
scores indicate better blocking rules.

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
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
il_suggest_blocking(df, con = con)
#> # A tibble: 2 × 6
#>   rule       n_distinct coverage n_pairs pct_of_cartesian score
#>   <chr>           <int>    <dbl>   <int>            <dbl> <dbl>
#> 1 first_name         13        1       8             4.21 0.958
#> 2 surname             7        1      24            12.6  0.874
DBI::dbDisconnect(con, shutdown = TRUE)
```
