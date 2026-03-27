# Personal Name Comparison

A pre-built domain comparison for personal names. Combines exact
matching, Jaro-Winkler, and Jaro levels with thresholds tuned for
typical name variation.

## Usage

``` r
cl_name(...)
```

## Arguments

- ...:

  Reserved for future options.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_name())
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
