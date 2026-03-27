# Postcode Comparison

A pre-built domain comparison for postcodes. Supports exact matching
with optional geographic-proximity fallback for partial matches.

## Usage

``` r
cl_postcode(...)
```

## Arguments

- ...:

  Reserved for future options (e.g., geographic fallback).

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(postcode, cl_postcode())
#> Linkage Specification
#>   Comparisons (1):
#>     postcode : levels
#>   Blocking rules: (none)
```
