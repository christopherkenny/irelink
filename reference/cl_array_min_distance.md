# Pairwise Array Minimum Distance Comparison

Creates comparison levels based on the best-matching pair of values
across two array columns. For each record pair, every element of the
left array is compared against every element of the right array; the
best score (maximum similarity for `'jaro_winkler'`, minimum distance
for `'levenshtein'`) is then tested against each threshold. Equivalent
to splink's `PairwiseStringDistanceFunctionAtThresholds`.

## Usage

``` r
cl_array_min_distance(fn = c("jaro_winkler", "levenshtein"), ...)
```

## Arguments

- fn:

  Distance function: `'jaro_winkler'` (default) or `'levenshtein'`. For
  `'jaro_winkler'`, thresholds are similarity scores (0–1, descending,
  strictest first). For `'levenshtein'`, thresholds are edit distances
  (non-negative integers, ascending, strictest first).

- ...:

  Numeric thresholds, from strictest to most lenient.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Details

On DuckDB the pairwise comparison runs in SQL via an UNNEST cross-join
scalar subquery. On SQLite it falls back to an R-side nested apply.

## Examples

``` r
# Jaro-Winkler: best pairwise similarity >= 0.9 or >= 0.7
il_spec() |>
  il_compare(aliases, cl_array_min_distance('jaro_winkler', 0.9, 0.7))
#> Linkage Specification
#>   Comparisons (1):
#>     aliases : array_min_distance
#>   Blocking rules: (none)

# Levenshtein: best pairwise edit distance <= 1 or <= 2
il_spec() |>
  il_compare(aliases, cl_array_min_distance('levenshtein', 1, 2))
#> Linkage Specification
#>   Comparisons (1):
#>     aliases : array_min_distance
#>   Blocking rules: (none)
```
