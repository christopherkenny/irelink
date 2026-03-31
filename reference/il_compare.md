# Add a Comparison Layer to a Specification

Declares how one or more columns should be compared when scoring record
pairs. Each call accumulates a new layer onto the spec, following the
same stacking pattern as
[`ggplot2::geom_point()`](https://ggplot2.tidyverse.org/reference/geom_point.html)
layers.

## Usage

``` r
il_compare(spec, col, method, ..., transform = NULL)
```

## Arguments

- spec:

  An `il_spec` object (piped in).

- col:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Column(s) to compare. Accepts bare names,
  [`c()`](https://rdrr.io/r/base/c.html), and tidyselect helpers.

- method:

  A comparison helper object created by a `cl_*()` function such as
  [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md)
  or
  [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md).

- ...:

  Reserved for future use.

- transform:

  An optional transformation function applied to both left and right
  column values *before* comparison. Common choices include `tolower`,
  `toupper`, and `trimws`, which are automatically translated to SQL
  when a database backend is available. Custom functions work on the
  R-side path only.

## Value

An updated `il_spec` (a new copy; the input is not modified).

## Details

`col` accepts tidyselect expressions: a bare column name,
`c(col_a, col_b)`, or helpers such as
[`tidyselect::starts_with()`](https://tidyselect.r-lib.org/reference/starts_with.html).
When multiple columns are targeted, each receives its own comparison
layer with the same method, mirroring `gt::fmt_number()`'s `columns`
argument.

## Examples

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_date_diff(days(30), days(365)))

# Apply a transform before comparing
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7), transform = tolower)
```
