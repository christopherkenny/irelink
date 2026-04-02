# Compose Custom Comparison Levels

Assembles an ordered list of comparison levels from individual level
constructors. Use this when the built-in `cl_*()` helpers do not fit and
you need full control over the level hierarchy. Analogous to writing a
custom
[`ggplot2::stat_identity()`](https://ggplot2.tidyverse.org/reference/stat_identity.html)
layer.

## Usage

``` r
cl_levels(..., term_frequency = FALSE)
```

## Arguments

- ...:

  Level objects created by
  [`cl_null()`](http://christophertkenny.com/irelink/reference/cl_null.md),
  [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md),
  [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md),
  [`cl_else()`](http://christophertkenny.com/irelink/reference/cl_else.md),
  and similar helpers.

- term_frequency:

  Logical. If `TRUE`, adjust match weights by value frequency at the
  highest comparison level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(
    name,
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_jaro_winkler(0.95),
      cl_jaro_winkler(0.88),
      cl_else(),
      term_frequency = TRUE
    )
  )
#> Linkage Specification
#>   Comparisons (1):
#>     name : levels
#>   Blocking rules: (none)
```
