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

  A DBI connection.

## Value

`con`, invisibly.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
# ... exploratory work that may have created several irelink models ...
il_cleanup_all(con)
DBI::dbDisconnect(con, shutdown = TRUE)
```
