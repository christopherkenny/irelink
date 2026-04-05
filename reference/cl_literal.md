# Literal Value Comparison

Creates a comparison level that checks whether a column equals a fixed
literal value on the left record, right record, or both. Equivalent to
splink's `LiteralMatchLevel`. Useful as a gate inside
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md)
to restrict a comparison to records with a known value (e.g., only
compare names when `country = 'US'`).

## Usage

``` r
cl_literal(value, side = c("both", "left", "right"))
```

## Arguments

- value:

  A scalar value to compare against. Character values are quoted in the
  generated SQL; numerics are not.

- side:

  Which record to check: `'both'` (default), `'left'`, or `'right'`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md).

## Examples

``` r
il_spec() |>
  il_compare(
    country,
    cl_levels(
      cl_null(),
      cl_literal('US', side = 'both'),
      cl_exact(),
      cl_else()
    )
  )
#> Linkage Specification
#>   Comparisons (1):
#>     country : levels
#>   Blocking rules: (none)
```
