# Compute String Similarity Scores

Computes multiple string-similarity metrics between two strings in a
single call. No database connection is required. Useful for quick
exploration of how names or other text fields compare.

## Usage

``` r
il_string_similarity(a, b)
```

## Arguments

- a:

  A character string.

- b:

  A character string.

## Value

A single-row tibble with columns `jaro`, `jaro_winkler`, `levenshtein`,
`damerau_levenshtein`, and `jaccard`.

## Examples

``` r
il_string_similarity('John', 'Jon')
#> # A tibble: 1 × 5
#>   jaro_winkler  jaro levenshtein jaccard cosine
#>          <dbl> <dbl>       <int>   <dbl>  <dbl>
#> 1        0.933 0.917           1    0.25  0.408
```
