# Create a Distance in Miles

A tagged-value constructor that marks a numeric threshold as a distance
in miles. Converted to kilometres internally by
[`cl_geo_distance()`](http://christophertkenny.com/irelink/reference/cl_geo_distance.md).

## Usage

``` r
mi(n)
```

## Arguments

- n:

  A non-negative numeric value.

## Value

A tagged numeric with class `il_mi`.

## Examples

``` r
il_spec() |>
  il_compare(c(lat, lon), cl_geo_distance(mi(3), mi(30)))
#> Linkage Specification
#>   Comparisons (1):
#>     lat, lon : geo_distance
#>   Blocking rules: (none)
```
