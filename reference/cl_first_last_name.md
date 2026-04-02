# First Name and Last Name Comparison with Swap Detection

An American-English alias for
[`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md).
Compares first and last name columns, including a swap-detection level
for accidentally transposed names. Pass this to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
on the first-name column and supply the companion last-name column via
`last_name`.

## Usage

``` r
cl_first_last_name(last_name = "last_name", term_frequency = FALSE)
```

## Arguments

- last_name:

  Name of the last name column in the data. Defaults to `'last_name'`.

- term_frequency:

  Logical. If `TRUE`, adjust match weights by name frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_first_last_name())
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
