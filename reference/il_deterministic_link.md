# Deterministic Record Linkage

Finds exact-match record pairs using the blocking rules in the
specification, without requiring probabilistic training. This is a
common first step before probabilistic linkage. Pairs that match on all
blocking columns are returned directly.

## Usage

``` r
il_deterministic_link(
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
  [dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html),
  or character table name (first or only dataset).

- ...:

  Additional datasets for multi-table linkage.

- spec:

  An `il_spec` object with blocking rules defined via
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md).

- con:

  A DBI connection object from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).
  Optional when `.data` is a
  [dbplyr::tbl_lazy](https://dbplyr.tidyverse.org/reference/tbl_lazy.html).

- link_type:

  One of `"dedupe"` (default), `"link"`, or `"link_and_dedupe"`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
of exact-match record pairs.

## Examples

``` r
df <- data.frame(
  unique_id = 1:20,
  first_name = c(
    'John', 'Jon', 'Jane', 'Jane', 'Bob',
    'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
    'John', 'Jon', 'Jane', 'Janet', 'Bob',
    'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
  ),
  surname = c(
    'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Brown', 'White', 'White',
    'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Browne', 'White', 'White'
  ),
  dob = c(
    '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
    '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
    '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
    '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
    '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
  ),
  city = c(
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
  ),
  email = c(
    'john@example.com', 'jon@example.com', 'jane@example.com',
    'jane@example.com', 'bob@example.com', 'bobby@example.com',
    'alice@example.com', 'alicia@example.com', 'tom@example.com',
    'thomas@example.com', 'john@example.com', 'jon@example.com',
    'jane@example.com', 'janet@example.com', 'bob@example.com',
    'robert@example.com', 'alice@example.com', 'alison@example.com',
    'tom@example.com', 'tomas@example.com'
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpye6umx/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(first_name, surname, dob)

exact_matches <- il_deterministic_link(df, spec = spec, con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
```
