# Forename and Surname Comparison with Swap Detection

A pre-built domain comparison that compares forename and surname
columns, including a cross-field swap-detection level (where first name
and surname are accidentally transposed). Pass this to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
on the forename/first-name column and supply the companion
surname/last-name column via `surname`.

## Usage

``` r
cl_forename_surname(surname = "surname", term_frequency = FALSE)
```

## Arguments

- surname:

  Name of the surname column in the data. Defaults to `'surname'`.

- term_frequency:

  Logical. If `TRUE`, adjust match weights by name frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Details

See also
[`cl_first_last_name()`](http://christophertkenny.com/irelink/reference/cl_first_last_name.md)
for an American-English alias.

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_forename_surname(surname = 'last_name'))
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
