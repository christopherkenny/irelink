# Attach a Saved Model to Fresh Data

Takes a loaded (or existing) `il_model` and binds it to new data and a
fresh database connection, producing a model ready for
[`predict()`](https://rdrr.io/r/stats/predict.html) or further training.
Accepts in-memory data frames, dbplyr lazy table references, or
character table names.

## Usage

``` r
il_attach(model, .data, ..., con = NULL, link_type = NULL)
```

## Arguments

- model:

  An `il_model` object, typically from
  [`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md).

- .data:

  A data frame, tibble, dbplyr `tbl_lazy`, or character table name. The
  first (or only) input dataset.

- ...:

  Additional datasets for multi-table linkage.

- con:

  A DBI connection object. Optional when `.data` is a `tbl_lazy` — the
  connection is extracted from the table reference.

- link_type:

  Optionally override the model's link type. If `NULL` (default), uses
  the link type stored in the model.

## Value

The model, now connected to `con` with data uploaded, ready for
[`predict()`](https://rdrr.io/r/stats/predict.html),
[`il_find_matches()`](http://christophertkenny.com/irelink/reference/il_find_matches.md),
or further training.

## Details

This is the key function for the production workflow: train once with
[`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
→ save with
[`il_save()`](http://christophertkenny.com/irelink/reference/il_save.md)
→ later, load with
[`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md)
and attach to new data with `il_attach()`.

The loaded model's trained parameters (m, u, prior) are preserved. You
can immediately call [`predict()`](https://rdrr.io/r/stats/predict.html)
on the attached model, or continue training with
[`il_estimate_em()`](http://christophertkenny.com/irelink/reference/il_estimate_em.md)
using the existing parameters as a warm start.

## Examples

``` r
# \donttest{
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)
model <- il_model(fake_1000, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
path <- tempfile(fileext = '.rds')
il_save(model, path)
DBI::dbDisconnect(con, shutdown = TRUE)
con2 <- DBI::dbConnect(duckdb::duckdb())
loaded <- il_load(path)
model2 <- il_attach(loaded, fake_1000, con = con2)
DBI::dbDisconnect(con2, shutdown = TRUE)
# }
```
