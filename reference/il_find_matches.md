# Find Matches for New Records

Scores new records against the data already loaded into a trained model.
Useful for real-time or incremental matching where new records arrive
after the model has been trained.

## Usage

``` r
il_find_matches(model, new_records, threshold = 0.85)
```

## Arguments

- model:

  A trained `il_model` object.

- new_records:

  A data frame, dbplyr `tbl_lazy`, or character table name of new
  records to match against the model's existing data.

- threshold:

  A numeric value between 0 and 1. Only matches at or above this
  probability are returned. Defaults to `0.85`.

## Value

An `il_compared` tibble of scored pairs between new records and existing
data.

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
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
#> EM trained: first_name and dob | skipped (blocked on): surname
new_df <- data.frame(
  first_name = 'Jhon', surname = 'Smith',
  dob = '1990-01-15', city = 'London'
)

il_find_matches(model, new_df, threshold = 0.5)
#> # A tibble: 3 × 4
#>   unique_id_l unique_id_r match_weight match_probability
#>         <int>       <int>        <dbl>             <dbl>
#> 1           1          11         3.86             0.989
#> 2           1           1         3.86             0.989
#> 3           1           2         3.86             0.989
DBI::dbDisconnect(con, shutdown = TRUE)
```
