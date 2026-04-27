# Create a Duration in Days

A tagged-value constructor that marks a numeric threshold as a number of
days. Inspired by `gt::px()` and `gt::pct()`. Use inside
[`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
for self-documenting, unit-safe thresholds.

## Usage

``` r
days(n)
```

## Arguments

- n:

  A non-negative numeric value.

## Value

A tagged numeric with class `il_days`.

## Examples

``` r
il_spec() |>
  il_compare(dob, cl_date_diff(days(30), days(365)))
#> Linkage Specification
#>   Comparisons (1):
#>     dob : date_diff
#>   Blocking rules: (none)
```
