# Jaro-Winkler String Similarity Comparison

Creates comparison levels based on the Jaro-Winkler similarity score (0
to 1). Thresholds are passed as unnamed arguments ordered from strictest
to most lenient — the same direction you would read them in a waterfall
chart.

## Usage

``` r
cl_jaro_winkler(...)
```

## Arguments

- ...:

  Numeric thresholds between 0 and 1, ordered from strictest to most
  lenient (e.g., `0.9, 0.7`).

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9))
#> Linkage Specification
#>   Comparisons (2):
#>     first_name : jaro_winkler
#>     surname : jaro_winkler
#>   Blocking rules: (none)
```
