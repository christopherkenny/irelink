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
  first_name = c("John", "Jon", "Jane", "Jane", "Bob",
                  "Bobby", "Alice", "Alicia", "Tom", "Thomas",
                  "John", "Jon", "Jane", "Janet", "Bob",
                  "Robert", "Alice", "Alison", "Tom", "Tomas"),
  surname = c("Smith", "Smith", "Doe", "Doe", "Jones",
              "Jones", "Brown", "Brown", "White", "White",
              "Smith", "Smyth", "Doe", "Doe", "Jones",
              "Jones", "Brown", "Browne", "White", "White"),
  dob = c("1990-01-01", "1990-01-01", "1985-06-15", "1985-06-15",
          "2000-12-01", "2000-12-01", "1975-03-22", "1975-03-22",
          "1988-07-04", "1988-07-04", "1990-01-01", "1990-01-02",
          "1985-06-15", "1985-06-16", "2000-12-01", "2000-12-02",
          "1975-03-22", "1975-03-23", "1988-07-04", "1988-07-05"),
  city = c("London", "London", "Paris", "Paris", "Berlin",
           "Berlin", "Rome", "Rome", "Madrid", "Madrid",
           "London", "London", "Paris", "Paris", "Berlin",
           "Berlin", "Rome", "Rome", "Madrid", "Madrid"),
  email = c("john@example.com", "jon@example.com", "jane@example.com",
            "jane@example.com", "bob@example.com", "bobby@example.com",
            "alice@example.com", "alicia@example.com", "tom@example.com",
            "thomas@example.com", "john@example.com", "jon@example.com",
            "jane@example.com", "janet@example.com", "bob@example.com",
            "robert@example.com", "alice@example.com", "alison@example.com",
            "tom@example.com", "tomas@example.com")
)
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))

il_parameters(model)
#> # A tibble: 6 × 4
#>   comparison level          m      u
#>   <chr>      <chr>      <dbl>  <dbl>
#> 1 first_name match     0.876  0.105 
#> 2 first_name non_match 0.124  0.895 
#> 3 surname    match     0.967  0.142 
#> 4 surname    non_match 0.0328 0.858 
#> 5 dob        match     0.821  0.0789
#> 6 dob        non_match 0.179  0.921 
DBI::dbDisconnect(con)
```
