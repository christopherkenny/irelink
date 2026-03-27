# Exact Equality Comparison

Creates a comparison level that scores an exact match on a column.
Optionally applies term-frequency adjustments so that rare values (e.g.,
an uncommon surname) receive higher match weights than common ones.

## Usage

``` r
cl_exact(term_frequency = FALSE)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by value frequency. Defaults
  to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(city, cl_exact()) |>
  il_compare(county, cl_exact(term_frequency = TRUE))
#> Linkage Specification
#>   Comparisons (2):
#>     city : exact
#>     county : exact
#>   Blocking rules: (none)
```
