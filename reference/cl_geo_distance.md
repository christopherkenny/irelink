# Geographic Distance Comparison

Creates comparison levels based on the great-circle distance between two
latitude/longitude pairs. Thresholds should use the unit helpers
[`km()`](http://christophertkenny.com/irelink/reference/km.md) or
[`mi()`](http://christophertkenny.com/irelink/reference/mi.md) for
clarity.

## Usage

``` r
cl_geo_distance(...)
```

## Arguments

- ...:

  Distance thresholds created by
  [`km()`](http://christophertkenny.com/irelink/reference/km.md) or
  [`mi()`](http://christophertkenny.com/irelink/reference/mi.md),
  ordered from strictest to most lenient.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(c(lat, lon), cl_geo_distance(km(5), km(50)))
#> Linkage Specification
#>   Comparisons (1):
#>     lat, lon : geo_distance
#>   Blocking rules: (none)

# Use miles instead
il_spec() |>
  il_compare(c(lat, lon), cl_geo_distance(mi(3), mi(30)))
#> Linkage Specification
#>   Comparisons (1):
#>     lat, lon : geo_distance
#>   Blocking rules: (none)
```
