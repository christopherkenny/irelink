# Batch String Similarity Scores

Computes string-similarity metrics between two columns of a data frame
or database table. Useful for profiling data quality and choosing
comparison thresholds. Rows where either column is missing are omitted.

## Usage

``` r
il_comparator_score(.data, col_1, col_2, con = NULL)
```

## Arguments

- .data:

  A data frame or character table name. Table names require `con`.

- col_1, col_2:

  Column names (unquoted or character).

- con:

  A DBI connection from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).
  If `NULL`, uses R-side computation.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with the two input columns and metric columns `jaro_winkler`, `jaro`,
`levenshtein`, `jaccard`, and `cosine`. Unsupported SQL-backend metrics
are present as `NA`. The result has S3 class `il_comparator_score`.

## Details

With `con = NULL`, all metrics are computed in R with
[`stringdist::stringdist()`](https://rdrr.io/pkg/stringdist/man/stringdist.html).
With a [`duckdb::duckdb()`](https://r.duckdb.org/reference/duckdb.html)
or PostgreSQL connection, computation is pushed to SQL. SQL backends
return the same column schema but may leave unsupported metrics as `NA`:
DuckDB currently computes `jaro_winkler`, `jaro`, `levenshtein`, and
`jaccard`; PostgreSQL computes `levenshtein` and a `jaro_winkler`
compatibility column backed by trigram `similarity()`.

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
