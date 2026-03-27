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

  A data frame or tibble. The first (or only) input dataset.

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
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)

model <- il_model(df, spec = spec, con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
```
