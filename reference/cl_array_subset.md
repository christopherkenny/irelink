# Array Subset Comparison

Creates a comparison level that matches when the smaller of two array
columns is a complete subset of the larger. In other words, every
element of the smaller array appears in the larger one.

## Usage

``` r
cl_array_subset()
```

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Details

On DuckDB and PostgreSQL this is computed in SQL using
`ARRAY_LENGTH(ARRAY_INTERSECT(...)) = LEAST(ARRAY_LENGTH(...))`. On
SQLite it falls back to an R-side set check.

## Examples

``` r
il_spec() |>
  il_compare(qualifications, cl_array_subset())
#> Linkage Specification
#>   Comparisons (1):
#>     qualifications : array_subset
#>   Blocking rules: (none)
```
