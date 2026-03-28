# Profile Column Value Distributions

Computes summary statistics and value-frequency distributions for
selected columns of a data frame. Useful for understanding data quality
before defining comparison rules.

## Usage

``` r
il_profile(.data, ..., con, top_n = NULL, bottom_n = NULL)
```

## Arguments

- .data:

  A data frame or tibble to profile.

- ...:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Columns to profile. If empty, all columns are profiled.

- con:

  A DBI connection object used for computation.

- top_n:

  Integer. Number of most-frequent values to return per column. Defaults
  to `NULL` (return all values).

- bottom_n:

  Integer. Number of least-frequent values to return per column.
  Defaults to `NULL` (return all values).

## Value

A tibble of per-column summary statistics.

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
il_profile(df, first_name, surname, con = con, top_n = 5)
#> # A tibble: 10 × 3
#>    column     value     n
#>    <chr>      <chr> <dbl>
#>  1 first_name Jane      3
#>  2 first_name Jon       2
#>  3 first_name Bob       2
#>  4 first_name John      2
#>  5 first_name Alice     2
#>  6 surname    White     4
#>  7 surname    Doe       4
#>  8 surname    Jones     4
#>  9 surname    Smith     3
#> 10 surname    Brown     3
DBI::dbDisconnect(con, shutdown = TRUE)
```
