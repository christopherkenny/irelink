# Extract Waterfall Data for a Single Pair

Returns a tidy tibble showing how each comparison contributed to the
total match weight for a specific record pair. Designed for use with
[`ggplot2::geom_col()`](https://ggplot2.tidyverse.org/reference/geom_bar.html)
and
[`ggplot2::coord_flip()`](https://ggplot2.tidyverse.org/reference/coord_flip.html).

## Usage

``` r
il_waterfall(pairs, which = 1L)
```

## Arguments

- pairs:

  An `il_compared` tibble from
  [`predict.il_model()`](http://christophertkenny.com/irelink/reference/predict.il_model.md).

- which:

  An integer index identifying which row (pair) to decompose. Defaults
  to `1L`.

## Value

A tibble with columns `step`, `order`, `contribution`, `direction`,
`start`, and `end`. The rows include the prior odds, one row per
comparison contribution, and a final total.

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
pairs <- predict(model, threshold = 0.5)

il_waterfall(pairs, which = 1)
#> # A tibble: 5 × 6
#>   step       order contribution direction start   end
#>   <chr>      <int>        <dbl> <chr>     <dbl> <dbl>
#> 1 Prior          1        -4.25 prior      0    -4.25
#> 2 first_name     2         2.90 positive  -4.25 -1.34
#> 3 surname        3         2.66 positive  -1.34  1.32
#> 4 dob            4         3.24 positive   1.32  4.56
#> 5 Final          5         4.56 final      0     4.56
DBI::dbDisconnect(con, shutdown = TRUE)
```
