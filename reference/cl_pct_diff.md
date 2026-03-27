# Numeric Percentage Difference Comparison

Creates comparison levels based on the relative percentage difference
between two numeric values. Thresholds are fractions (e.g., `0.05` for
5%), ordered from strictest to most lenient.

## Usage

``` r
cl_pct_diff(...)
```

## Arguments

- ...:

  Numeric percentage thresholds, ordered from strictest to most lenient
  (e.g., `0.05, 0.2`).

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(income, cl_pct_diff(0.05, 0.2))
#> Linkage Specification
#>   Comparisons (1):
#>     income : pct_diff
#>   Blocking rules: (none)
```
