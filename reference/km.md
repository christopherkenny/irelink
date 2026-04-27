# Create a Distance in Kilometres

A tagged-value constructor that marks a numeric threshold as a distance
in kilometres. Use inside
[`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md)
for self-documenting thresholds.

## Usage

``` r
km(n)
```

## Arguments

- n:

  A non-negative numeric value.

## Value

A tagged numeric with class `il_km`.

## Examples

``` r
il_spec() |>
  il_compare(c(lat, lon), cl_distance_km(km(5), km(50)))
#> Linkage Specification
#>   Comparisons (2):
#>     lat : distance_km
#>     lon : distance_km
#>   Blocking rules: (none)
```
