# Email Address Comparison

A pre-built domain comparison for email addresses. Provides levels for
exact match, username-only match, and domain-only match.

## Usage

``` r
cl_email(term_frequency = FALSE)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by email frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(email, cl_email())
#> Linkage Specification
#>   Comparisons (1):
#>     email : levels
#>   Blocking rules: (none)
```
