# Date Difference Comparison

Creates comparison levels based on the absolute difference between two
dates. Thresholds should use the unit helpers
[`days()`](http://christophertkenny.com/irelink/reference/days.md),
[`months()`](http://christophertkenny.com/irelink/reference/months.md),
or [`years()`](http://christophertkenny.com/irelink/reference/years.md)
for self-documenting, unit-safe specifications. Bare numerics are
interpreted as days.

## Usage

``` r
cl_date_diff(...)
```

## Arguments

- ...:

  Duration thresholds created by
  [`days()`](http://christophertkenny.com/irelink/reference/days.md),
  [`months()`](http://christophertkenny.com/irelink/reference/months.md),
  or
  [`years()`](http://christophertkenny.com/irelink/reference/years.md),
  ordered from strictest to most lenient.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(dob, cl_date_diff(days(30), days(365)))
#> Linkage Specification
#>   Comparisons (1):
#>     dob : date_diff
#>   Blocking rules: (none)

# Mix units freely
il_spec() |>
  il_compare(dob, cl_date_diff(months(1), years(1)))
#> Linkage Specification
#>   Comparisons (1):
#>     dob : date_diff
#>   Blocking rules: (none)
```
