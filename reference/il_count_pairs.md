# Count Candidate Pairs Under Blocking Rules

Estimates how many record pairs each blocking rule generates without
performing full comparisons. Useful for tuning blocking strategies
before training — too many pairs is slow; too few misses matches.

## Usage

``` r
il_count_pairs(.data, ..., con, link_type = c("dedupe", "link"))
```

## Arguments

- .data:

  A data frame or tibble (first or only dataset).

- ...:

  Blocking rules created by
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md),
  and optionally additional data frames for linkage.

- con:

  A DBI connection object used for computation.

- link_type:

  One of `"dedupe"` (default) or `"link"`.

## Value

A tibble with columns `rule`, `pairs_generated`, `cumulative_pairs`, and
`pct_of_cartesian`.

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
con <- DBI::dbConnect(duckdb::duckdb())
il_count_pairs(
  df,
  block_on(surname),
  block_on(first_name),
  con = con
)
#> # A tibble: 2 × 2
#>   rule       n_pairs
#>   <chr>        <int>
#> 1 surname         24
#> 2 first_name       8
DBI::dbDisconnect(con, shutdown = TRUE)
```
