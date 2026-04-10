# Batch String Similarity Scores

Computes multiple string-similarity metrics between two columns of a
data frame. Useful for profiling data quality and choosing comparison
thresholds. On DuckDB, computation is pushed to SQL.

## Usage

``` r
il_comparator_score(.data, col_1, col_2, con = NULL)
```

## Arguments

- .data:

  A data frame or character table name.

- col_1, col_2:

  Column names (unquoted or character).

- con:

  A DBI connection. If `NULL`, uses R-side computation.

## Value

A tibble with `col_1`, `col_2`, and similarity columns: `jaro_winkler`,
`jaro`, `levenshtein`, `jaccard`, and `cosine`. S3 class
`il_comparator_score`.

## Examples

``` r
df <- data.frame(
  name_l = c('John', 'Jane', 'Bob'),
  name_r = c('Jon', 'Janet', 'Bobby')
)
il_comparator_score(df, name_l, name_r)
#> # A tibble: 3 × 7
#>   name_l name_r jaro_winkler  jaro levenshtein jaccard cosine
#>   <chr>  <chr>         <dbl> <dbl>       <int>   <dbl>  <dbl>
#> 1 John   Jon           0.933 0.917           1    0.25  0.408
#> 2 Jane   Janet         0.96  0.933           1    0.75  0.866
#> 3 Bob    Bobby         0.907 0.867           2    0.5   0.707
```
