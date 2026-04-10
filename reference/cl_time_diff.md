# Time Difference Comparison

Creates comparison levels based on the absolute difference between two
datetime (timestamp) values. Thresholds should use the unit helpers
[`seconds()`](http://christophertkenny.com/irelink/reference/seconds.md),
[`minutes()`](http://christophertkenny.com/irelink/reference/minutes.md),
[`hours()`](http://christophertkenny.com/irelink/reference/hours.md),
[`days()`](http://christophertkenny.com/irelink/reference/days.md),
[`months()`](http://christophertkenny.com/irelink/reference/months.md),
or [`years()`](http://christophertkenny.com/irelink/reference/years.md)
for self-documenting, unit-safe specifications. Bare numerics are
interpreted as seconds.

## Usage

``` r
cl_time_diff(...)
```

## Arguments

- ...:

  Duration thresholds created by
  [`seconds()`](http://christophertkenny.com/irelink/reference/seconds.md),
  [`minutes()`](http://christophertkenny.com/irelink/reference/minutes.md),
  [`hours()`](http://christophertkenny.com/irelink/reference/hours.md),
  [`days()`](http://christophertkenny.com/irelink/reference/days.md),
  [`months()`](http://christophertkenny.com/irelink/reference/months.md),
  or
  [`years()`](http://christophertkenny.com/irelink/reference/years.md),
  ordered from strictest to most lenient.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Details

This extends
[`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
to support sub-day precision for timestamp columns. Use
[`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)
for date-only columns.

## Examples

``` r
il_spec() |>
  il_compare(timestamp, cl_time_diff(minutes(5), hours(1)))
#> Linkage Specification
#>   Comparisons (1):
#>     timestamp : time_diff
#>   Blocking rules: (none)

# Mix units freely
il_spec() |>
  il_compare(timestamp, cl_time_diff(seconds(30), minutes(10), hours(2)))
#> Linkage Specification
#>   Comparisons (1):
#>     timestamp : time_diff
#>   Blocking rules: (none)
```
