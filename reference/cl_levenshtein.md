# Levenshtein Edit-Distance Comparison

Creates comparison levels based on the Levenshtein edit distance
(minimum number of single-character insertions, deletions, or
substitutions). Thresholds are integer counts, ordered from strictest
(smallest distance) to most lenient.

## Usage

``` r
cl_levenshtein(..., term_frequency = FALSE)
```

## Arguments

- ...:

  Integer distance thresholds, ordered from strictest to most lenient
  (e.g., `1, 2`).

- term_frequency:

  Logical. If `TRUE`, adjust match weights by value frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(name, cl_levenshtein(1, 2))
#> Linkage Specification
#>   Comparisons (1):
#>     name : levenshtein
#>   Blocking rules: (none)
```
