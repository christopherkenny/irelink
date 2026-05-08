# Add a Comparison Layer to a Specification

Declares how one or more columns should be compared when scoring record
pairs. Each call adds one comparison to the specification.

## Usage

``` r
il_compare(
  spec,
  col,
  method,
  ...,
  transform = NULL,
  tf_adjustment_weight = 1,
  tf_minimum_u_value = 0
)
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

- tf_adjustment_weight:

  Numeric power to raise the term-frequency Bayes factor to. A value of
  `1.0` (the default) applies the full adjustment. Use `0` to disable it
  entirely. Only relevant when the comparison method has
  `term_frequency = TRUE`.

- tf_minimum_u_value:

  Numeric floor for the term-frequency denominator. When both TF values
  are below this threshold, it is used instead, preventing
  unrealistically large match weights for very rare terms. Defaults to
  `0.0` (no floor).

## Value

An updated copy of `spec`.

## Details

`col` accepts tidyselect expressions: a bare column name,
`c(col_a, col_b)`, or helpers such as
[`tidyselect::starts_with()`](https://tidyselect.r-lib.org/reference/starts_with.html).
When multiple columns are targeted, each receives its own comparison
layer with the same method.

## Examples

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_date_diff(days(30), days(365)))

# Apply a transform before comparing
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7), transform = tolower)

# Scale TF adjustment weight
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, term_frequency = TRUE),
    tf_adjustment_weight = 0.5, tf_minimum_u_value = 0.001
  )
```
