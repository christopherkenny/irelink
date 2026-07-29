# Comparison Vector Distribution

Computes the distribution of gamma patterns (agreement vectors) across
record pairs. Each unique combination of gamma values across comparisons
is a "comparison vector". This function counts how often each pattern
occurs.

## Usage

``` r
il_comparison_vectors(model, blocking = NULL, limit = NULL)
```

## Arguments

- model:

  A trained `il_model`.

- blocking:

  A blocking rule created by
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md).
  If `NULL`, uses all blocking rules from the model spec.

- limit:

  Maximum number of pairs to sample. Defaults to `NULL` (all pairs).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per unique comparison vector and columns `gamma_<col>` for
each comparison plus `count` (number of pairs with that pattern) and
`proportion`. Class `il_comparison_vectors`.

## Details

On DuckDB, the computation runs entirely in SQL.

## Examples

``` r
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
  il_compare(first_name, cl_exact()) |>
  il_compare(surname, cl_exact())
model <- il_model(fake_20, spec = spec, con = con)
vectors <- il_comparison_vectors(model)
ggplot2::autoplot(vectors)

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
