# Save a Model to Disk

Serializes a trained `il_model` object to `.json` or `.rds`, chosen from
`path`.

## Usage

``` r
il_save(model, path, overwrite = FALSE)
```

## Arguments

- model:

  A trained `il_model` object.

- path:

  A file path (character string) where the model will be saved.

- overwrite:

  If `TRUE`, overwrite an existing file at `path`. Defaults to `FALSE`.

## Value

`model`, invisibly.

## Details

`.json` writes Splink settings JSON. Other extensions write RDS. The
database connection and any in-database tables are not stored. Supply a
fresh connection with
[`il_attach()`](http://christophertkenny.com/irelink/reference/il_attach.md)
after loading.

JSON export preserves scoring and prediction behavior by lowering
comparisons and blocking rules to SQL. It does not guarantee exact
round-tripping of irelink helper structure such as transform functions
or structured blocking-rule fields.

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
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
#> EM trained: first_name and dob | skipped (blocked on): surname
tmp <- tempfile(fileext = '.rds')

il_save(model, tmp)
DBI::dbDisconnect(con, shutdown = TRUE)
```
