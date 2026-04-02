# ZIP Code Comparison

A pre-built domain comparison for US ZIP codes. Provides levels for
exact match, 5-digit prefix match (normalizes ZIP+4 against plain
5-digit codes), and 3-digit Sectional Center Facility (SCF) prefix
match. Accepts both plain 5-digit (`'90210'`) and ZIP+4 (`'90210-3456'`)
formats.

## Usage

``` r
cl_zip_code(term_frequency = FALSE)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by ZIP code frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(zip, cl_zip_code())
#> Linkage Specification
#>   Comparisons (1):
#>     zip : levels
#>   Blocking rules: (none)
```
