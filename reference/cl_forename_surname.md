# Forename and Surname Comparison with Swap Detection

A pre-built domain comparison that compares forename and surname
columns, including a cross-field swap-detection level (where first name
and surname are accidentally transposed).

## Usage

``` r
cl_forename_surname(...)
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
  il_compare(first_name, cl_forename_surname())
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
