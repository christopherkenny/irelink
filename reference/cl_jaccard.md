# Jaccard Set Similarity Comparison

Creates comparison levels based on the Jaccard index, the ratio of the
intersection to the union of character n-gram sets. Thresholds are
between 0 and 1, ordered from strictest to most lenient.

## Usage

``` r
cl_jaccard(...)
```

## Arguments

- ...:

  Numeric thresholds between 0 and 1, ordered from strictest to most
  lenient.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(name, cl_jaccard(0.9))
#> Linkage Specification
#>   Comparisons (1):
#>     name : jaccard
#>   Blocking rules: (none)
```
