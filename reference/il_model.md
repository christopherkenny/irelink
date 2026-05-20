# Create a Linkage Model

Binds one or more datasets to a specification and a database connection,
producing an untrained model. Accepts in-memory data frames,
[dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html)
table references, or character table names for data that already lives
in a database.

## Usage

``` r
il_model(
  .data,
  ...,
  spec,
  con = NULL,
  link_type = c("dedupe", "link", "link_and_dedupe")
)
```

## Arguments

- .data:

  A data frame,
  [`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html),
  [dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html),
  or character table name. The first (or only) input dataset. If no
  `unique_id` column is present, one is generated automatically.

- ...:

  Additional datasets for multi-table linkage (same types as `.data`).

- spec:

  An `il_spec` object built with
  [`il_spec()`](http://christophertkenny.com/irelink/reference/il_spec.md),
  [`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md),
  and
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md).

- con:

  A DBI connection object from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  (e.g., from `DBI::dbConnect(duckdb::duckdb())`). Optional when `.data`
  is a
  [dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html),
  the connection is extracted from the table reference.

- link_type:

  One of `"dedupe"` (default), `"link"`, or `"link_and_dedupe"`.

## Value

An untrained `il_model` object, ready for training verbs.

## Details

When `.data` is a
[dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html)
(from [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)),
the connection is extracted automatically and data stays in-database
with zero copying. A `unique_id` column is injected automatically if not
already present.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)

model <- il_model(fake_20, spec = spec, con = con)

# Database-backed: pass a dbplyr reference directly
DBI::dbWriteTable(con, 'my_data', fake_20, overwrite = TRUE)
tbl_ref <- dplyr::tbl(con, 'my_data')
model2 <- il_model(tbl_ref, spec = spec)
DBI::dbDisconnect(con, shutdown = TRUE)
```
