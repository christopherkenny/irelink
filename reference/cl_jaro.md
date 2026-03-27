# Jaro String Similarity Comparison

Creates comparison levels based on the Jaro similarity score (0 to 1). A
simpler variant of
[`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md)
without the prefix bonus.

## Usage

``` r
cl_jaro(...)
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
  il_compare(name, cl_jaro(0.9))
#> Linkage Specification
#>   Comparisons (1):
#>     name : jaro
#>   Blocking rules: (none)
```
