# Array Intersection Comparison

Creates comparison levels based on the number of shared elements between
two array or list columns. Thresholds are integer counts, ordered from
strictest (most shared elements required) to most lenient.

## Usage

``` r
cl_array_intersect(...)
```

## Arguments

- ...:

  Integer count thresholds, ordered from strictest to most lenient
  (e.g., `2, 1`).

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(tags, cl_array_intersect(2, 1))
#> Linkage Specification
#>   Comparisons (1):
#>     tags : array_intersect
#>   Blocking rules: (none)
```
