# Remove All irelink Temporary Tables from a Database

Drops every table or view whose name starts with `__il_` from a DBI
connection. This is intended as an explicit interactive escape hatch
after failed runs or exploratory sessions. Prefer
[`il_cleanup()`](http://christophertkenny.com/irelink/reference/il_cleanup.md)
when cleaning up a specific live model on a shared connection.

## Usage

``` r
il_cleanup_all(con)
```

## Arguments

- con:

  A DBI connection from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Value

`con`, invisibly.

## Examples

``` r
df <- data.frame(
  unique_id = 1:4,
  name = c('Ann', 'Anne', 'Bob', 'Rob')
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(name, cl_jaro_winkler(0.9)) |>
  il_block_on(name)
model <- il_model(df, spec = spec, con = con)

il_cleanup_all(con)
DBI::dbDisconnect(con, shutdown = TRUE)
```
