# Register Pre-Computed Term Frequency Tables

Allows you to supply pre-computed term frequency lookup tables instead
of having them computed automatically from the data. This is useful when
you have production TF tables from a larger dataset or want to reuse TF
values across multiple linkage runs.

## Usage

``` r
il_register_tf(model, col, tf_data, overwrite = FALSE)
```

## Arguments

- model:

  An `il_model` object.

- col:

  Character name of the comparison column.

- tf_data:

  A data frame with columns `<col>` and `tf_<col>`.

- overwrite:

  Logical. If `TRUE`, overwrite an existing TF table for this column.
  Defaults to `FALSE`.

## Value

The updated model, with the TF table registered in the database.

## Details

The supplied data must have exactly two columns: the value column (named
the same as the comparison column) and the frequency column (named
`tf_<col>`).

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
  il_block_on(surname)
model <- il_model(fake_20, spec = spec, con = con)
tf <- data.frame(
  first_name = c('John', 'Jane', 'Bob', 'Alice', 'Tom'),
  tf_first_name = rep(0.2, 5)
)
model <- il_register_tf(model, 'first_name', tf)
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
