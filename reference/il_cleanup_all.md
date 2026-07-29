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
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpzB4yCz/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
spec <- il_spec() |>
  il_compare(name, cl_jaro_winkler(0.9)) |>
  il_block_on(name)
model <- il_model(df, spec = spec, con = con)

il_cleanup_all(con)
DBI::dbDisconnect(con, shutdown = TRUE)
```
