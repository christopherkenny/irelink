# Create a Duration in Seconds

A tagged-value constructor that marks a numeric threshold as a number of
seconds. Use inside
[`cl_time_diff()`](http://christophertkenny.com/irelink/reference/cl_time_diff.md)
for self-documenting thresholds.

## Usage

``` r
seconds(n)
```

## Arguments

- n:

  A non-negative numeric value.

## Value

A tagged numeric with class `il_seconds`.

## Examples

``` r
il_spec() |>
  il_compare(timestamp, cl_time_diff(seconds(30), seconds(300)))
#> Linkage Specification
#>   Comparisons (1):
#>     timestamp : time_diff
#>   Blocking rules: (none)
```
