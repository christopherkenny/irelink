# Create a Duration in Years

A tagged-value constructor that marks a numeric threshold as a number of
years. Use inside
[`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
for self-documenting thresholds.

## Usage

``` r
years(n)
```

## Arguments

- n:

  A positive numeric value.

## Value

A tagged numeric with class `il_years`.

## Examples

``` r
il_spec() |>
  il_compare(dob, cl_date_diff(years(1)))
#> Linkage Specification
#>   Comparisons (1):
#>     dob : date_diff
#>   Blocking rules: (none)
```
