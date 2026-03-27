# Numeric Absolute Difference Comparison

Creates comparison levels based on the absolute difference between two
numeric values. Thresholds are ordered from strictest (smallest
permitted difference) to most lenient.

## Usage

``` r
cl_numeric_diff(...)
```

## Arguments

- ...:

  Numeric difference thresholds, ordered from strictest to most lenient
  (e.g., `1, 5`).

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(age, cl_numeric_diff(1, 5))
#> Linkage Specification
#>   Comparisons (1):
#>     age : numeric_diff
#>   Blocking rules: (none)
```
