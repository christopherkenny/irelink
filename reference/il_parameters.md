# Extract Model Parameters

Returns a tidy tibble of m and u probabilities for every comparison
level in the model. Designed for use with
[`ggplot2::geom_point()`](https://ggplot2.tidyverse.org/reference/geom_point.html).

## Usage

``` r
il_parameters(model)
```

## Arguments

- model:

  A trained `il_model` object.

## Value

A tibble with columns `comparison`, `level`, `m_prob`, and `u_prob`.

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
#> Comparisons surname overlap with the blocking rule and will not be updated.

il_parameters(model)
#> # A tibble: 8 × 4
#>   comparison gamma_level       m      u
#>   <chr>            <int>   <dbl>  <dbl>
#> 1 first_name           0 0.00917 0.832 
#> 2 first_name           1 0.203   0.0632
#> 3 first_name           2 0.788   0.105 
#> 4 surname              0 0.05    0.821 
#> 5 surname              1 0.05    0.0368
#> 6 surname              2 0.9     0.142 
#> 7 dob                  0 0.254   0.921 
#> 8 dob                  1 0.746   0.0789
DBI::dbDisconnect(con, shutdown = TRUE)
```
