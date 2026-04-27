# Create a Duration in Months

A tagged-value constructor that marks a numeric threshold as a number of
months. Use inside
[`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
for self-documenting thresholds.

## Usage

``` r
months(n)
```

## Arguments

- n:

  A non-negative numeric value.

## Value

A tagged numeric with class `il_months`.

## Examples

``` r
il_spec() |>
  il_compare(dob, cl_date_diff(months(1), months(12)))
#> Linkage Specification
#>   Comparisons (1):
#>     dob : date_diff
#>   Blocking rules: (none)
```
