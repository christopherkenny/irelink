# Comparison Vector Distribution

Computes the distribution of gamma patterns (agreement vectors) across
record pairs. Each unique combination of gamma values across comparisons
is a "comparison vector". This function counts how often each pattern
occurs.

## Usage

``` r
il_comparison_vectors(model, blocking = NULL, limit = NULL)
```

## Arguments

- model:

  A trained `il_model`.

- blocking:

  A blocking rule created by
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md).
  If `NULL`, uses all blocking rules from the model spec.

- limit:

  Maximum number of pairs to sample. Defaults to `NULL` (all pairs).

## Value

A tibble with one row per unique comparison vector and columns
`gamma_<col>` for each comparison plus `count` (number of pairs with
that pattern) and `proportion`. Class `il_comparison_vectors`.

## Details

On DuckDB/PostgreSQL, the computation runs entirely in SQL.

## Examples

``` r
if (FALSE) { # \dontrun{
vectors <- il_comparison_vectors(model)
autoplot(vectors)
} # }
```
