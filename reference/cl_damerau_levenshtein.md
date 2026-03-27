# Damerau-Levenshtein Edit-Distance Comparison

Creates comparison levels based on the Damerau-Levenshtein distance,
which extends
[`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md)
by also counting transpositions of two adjacent characters as a single
edit.

## Usage

``` r
cl_damerau_levenshtein(...)
```

## Arguments

- ...:

  Integer distance thresholds, ordered from strictest to most lenient.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(name, cl_damerau_levenshtein(1))
#> Linkage Specification
#>   Comparisons (1):
#>     name : damerau_levenshtein
#>   Blocking rules: (none)
```
