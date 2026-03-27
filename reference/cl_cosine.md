# Cosine Similarity Comparison

Creates comparison levels based on cosine similarity. Suitable for
numeric or vectorised columns. Thresholds are between 0 and 1, ordered
from strictest to most lenient.

## Usage

``` r
cl_cosine(...)
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
  il_compare(embedding, cl_cosine(0.8))
#> Linkage Specification
#>   Comparisons (1):
#>     embedding : cosine
#>   Blocking rules: (none)
```
