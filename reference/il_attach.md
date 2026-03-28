# Attach a Saved Model to Fresh Data

Takes a loaded (or existing) `il_model` and binds it to new data and a
fresh database connection, producing a model ready for
[`predict()`](https://rdrr.io/r/stats/predict.html) or further training.

## Usage

``` r
il_attach(model, .data, ..., con, link_type = NULL)
```

## Arguments

- model:

  An `il_model` object, typically from
  [`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md).

- .data:

  A data frame or tibble. The first (or only) input dataset.

- ...:

  Additional data frames for multi-table linkage.

- con:

  A DBI connection object (e.g., from
  `DBI::dbConnect(duckdb::duckdb())`).

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
if (FALSE) { # \dontrun{
# Production workflow: load a pre-trained model, attach to new data
loaded <- il_load('trained_model.json')
con <- DBI::dbConnect(duckdb::duckdb())
model <- il_attach(loaded, new_data, con = con)
pairs <- predict(model)
DBI::dbDisconnect(con, shutdown = TRUE)
} # }
```
