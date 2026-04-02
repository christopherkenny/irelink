# Date of Birth Comparison

A pre-built domain comparison for dates of birth. Combines
string-parsing, date-difference, and component-matching levels to handle
common date-of-birth errors (transpositions, partial dates).

## Usage

``` r
cl_dob(term_frequency = FALSE)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by date-of-birth frequency at
  the highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(dob, cl_dob())
#> Linkage Specification
#>   Comparisons (1):
#>     dob : levels
#>   Blocking rules: (none)
```
