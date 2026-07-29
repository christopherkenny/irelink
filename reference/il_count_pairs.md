# Count Candidate Pairs Under Blocking Rules

Estimates how many record pairs each blocking rule generates without
performing full comparisons. Useful for tuning blocking strategies
before training. Too many pairs is slow, while too few misses matches.

## Usage

``` r
il_count_pairs(.data, ..., con = NULL, link_type = c("dedupe", "link"))
```

## Arguments

- .data:

  A data frame,
  [dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html),
  or character table name (first or only dataset).

- ...:

  Blocking rules created by
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md),
  and optionally additional datasets for linkage.

- con:

  A DBI connection object from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).
  Optional when `.data` is a
  [dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html).

- link_type:

  One of `"dedupe"` (default) or `"link"`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with columns `rule` and `n_pairs`. When blocking rules are supplied, it
also includes `cumulative_pairs` and `pct_of_cartesian`.

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
#> ℹ /tmp/RtmpzB4yCz/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
il_count_pairs(
  df,
  block_on(surname),
  block_on(first_name),
  con = con
)
#> # A tibble: 2 × 4
#>   rule       n_pairs cumulative_pairs pct_of_cartesian
#>   <chr>        <dbl>            <dbl>            <dbl>
#> 1 surname         24               24             12.6
#> 2 first_name       8               25             13.2
DBI::dbDisconnect(con, shutdown = TRUE)
```
