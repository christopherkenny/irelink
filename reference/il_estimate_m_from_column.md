# Estimate Match (m) Parameters from a Label Column

Learns the m probabilities from a ground-truth identifier column (e.g.,
Social Security Number) present in the input data. Records sharing the
same label value are treated as true matches. This is an alternative to
[`il_estimate_m_from_labels()`](http://christophertkenny.com/irelink/reference/il_estimate_m_from_labels.md),
which requires a separate table of pairwise labels.

## Usage

``` r
il_estimate_m_from_column(model, label_col)
```

## Arguments

- model:

  An `il_model` object (piped in).

- label_col:

  The unquoted name of a column in the input data containing
  ground-truth entity identifiers.

## Value

An updated `il_model` with estimated m parameters.

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
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_exact()) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname)
model <- il_model(fake_20, spec = spec, con = con)
model <- il_estimate_u(model)

model <- il_estimate_m_from_column(model, city)
DBI::dbDisconnect(con, shutdown = TRUE)
```
