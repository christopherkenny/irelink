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
df <- fake_20
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_exact()) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)

model <- il_estimate_m_from_column(model, city)
DBI::dbDisconnect(con, shutdown = TRUE)
```
