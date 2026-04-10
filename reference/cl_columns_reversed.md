# Swap Detection for Two Columns

Creates a comparison level that fires when two column values are
transposed between the left and right records (e.g., first name and
surname accidentally swapped). This is a standalone equivalent of
splink's `ColumnsReversedLevel`.

## Usage

``` r
cl_columns_reversed(col_name_2, symmetrical = FALSE)
```

## Arguments

- col_name_2:

  Name of the second column (character). The first column is the one
  passed to
  [`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

- symmetrical:

  Logical. If `TRUE`, checks both directions:
  `l.col1 = r.col2 AND l.col2 = r.col1`. If `FALSE` (default), checks
  one direction only: `l.col1 = r.col2`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md).

## Details

Use inside
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md)
to add a swap-detection level to a custom comparison. For a ready-made
name comparison that already includes swap detection, see
[`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md).

## Examples

``` r
# Detect swapped first/last names inside a custom comparison
il_spec() |>
  il_compare(
    first_name,
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_columns_reversed('surname', symmetrical = TRUE),
      cl_else()
    )
  )
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
