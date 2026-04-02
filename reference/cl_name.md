# Personal Name Comparison

A pre-built domain comparison for personal names. Combines exact
matching, Jaro-Winkler, and Jaro levels with thresholds tuned for
typical name variation.

## Usage

``` r
cl_name(term_frequency = FALSE)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by name frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name(term_frequency = TRUE))
#> Linkage Specification
#>   Comparisons (2):
#>     first_name : levels
#>     surname : levels
#>   Blocking rules: (none)
```
