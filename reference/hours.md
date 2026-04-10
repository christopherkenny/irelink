# Create a Duration in Hours

A tagged-value constructor that marks a numeric threshold as a number of
hours. Use inside
[`cl_time_diff()`](http://christophertkenny.com/irelink/reference/cl_time_diff.md)
for self-documenting, unit-safe thresholds.

## Usage

``` r
hours(n)
```

## Arguments

- n:

  A positive numeric value.

## Value

A tagged numeric with class `il_hours`.

## Examples

``` r
il_spec() |>
  il_compare(timestamp, cl_time_diff(hours(2), hours(24)))
#> Linkage Specification
#>   Comparisons (1):
#>     timestamp : time_diff
#>   Blocking rules: (none)
```
