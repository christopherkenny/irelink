# Create a Duration in Minutes

A tagged-value constructor that marks a numeric threshold as a number of
minutes. Use inside
[`cl_time_diff()`](http://christophertkenny.com/irelink/reference/cl_time_diff.md)
for self-documenting thresholds.

## Usage

``` r
minutes(n)
```

## Arguments

- n:

  A positive numeric value.

## Value

A tagged numeric with class `il_minutes`.

## Examples

``` r
il_spec() |>
  il_compare(timestamp, cl_time_diff(minutes(5), minutes(60)))
#> Linkage Specification
#>   Comparisons (1):
#>     timestamp : time_diff
#>   Blocking rules: (none)
```
