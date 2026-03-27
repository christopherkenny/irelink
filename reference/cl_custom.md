# Custom SQL Comparison

Creates a comparison level from a raw SQL expression. Use this when none
of the built-in `cl_*()` helpers fit. The SQL should reference `l.` and
`r.` prefixed column names for the left and right records. Analogous to
`gt::md()` — a tagged-string helper with processing semantics.

## Usage

``` r
cl_custom(sql_expr, ...)
```

## Arguments

- sql_expr:

  A character string containing a valid SQL expression.

- ...:

  Reserved for future use.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(score, cl_custom("l.score + r.score > 10"))
#> Linkage Specification
#>   Comparisons (1):
#>     score : custom
#>   Blocking rules: (none)
```
