# Date of Birth Comparison

A pre-built domain comparison for dates of birth. Combines
string-parsing, date-difference, and component-matching levels to handle
common date-of-birth errors (transpositions, partial dates).

## Usage

``` r
cl_dob(...)
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
  il_compare(dob, cl_dob())
#> Linkage Specification
#>   Comparisons (1):
#>     dob : levels
#>   Blocking rules: (none)
```
