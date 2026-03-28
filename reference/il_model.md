# Create a Linkage Model

Binds one or more data frames to a specification and a database
connection, producing an untrained model. This is analogous to how
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) binds a
connection to a table name and returns a lazy reference.

## Usage

``` r
il_model(
  .data,
  ...,
  spec,
  con,
  link_type = c("dedupe", "link", "link_and_dedupe")
)
```

## Arguments

- .data:

  A data frame or tibble. The first (or only) input dataset. If no
  `unique_id` column is present, one is generated automatically.

- ...:

  Additional data frames for multi-table linkage.

- spec:

  An `il_spec` object built with
  [`il_spec()`](http://christophertkenny.com/irelink/reference/il_spec.md),
  [`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md),
  and
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md).

- con:

  A DBI connection object (e.g., from
  `DBI::dbConnect(duckdb::duckdb())`).

- link_type:

  One of `"dedupe"` (default), `"link"`, or `"link_and_dedupe"`.

## Value

An untrained `il_model` object, ready for training verbs.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)

model <- il_model(fake_20, spec = spec, con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
```
