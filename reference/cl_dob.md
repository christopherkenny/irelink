# Date of Birth Comparison

A pre-built domain comparison for dates of birth. Combines exact
matching, a Damerau-Levenshtein string check for transposed digits, and
configurable date-difference levels to handle common errors.

## Usage

``` r
cl_dob(
  thresholds = list(months(1), years(1), years(10)),
  term_frequency = FALSE
)
```

## Arguments

- thresholds:

  A list of unit-tagged threshold values created by
  [`days()`](http://christophertkenny.com/irelink/reference/days.md),
  [`months()`](http://christophertkenny.com/irelink/reference/months.md),
  or
  [`years()`](http://christophertkenny.com/irelink/reference/years.md),
  ordered from strictest to most lenient. Defaults to
  `list(months(1), years(1), years(10))`.

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

# Custom thresholds: within 7 days, 6 months, 2 years
il_spec() |>
  il_compare(dob, cl_dob(thresholds = list(days(7), months(6), years(2))))
#> Linkage Specification
#>   Comparisons (1):
#>     dob : levels
#>   Blocking rules: (none)
```
