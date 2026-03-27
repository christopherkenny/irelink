# irelink

`irelink` brings fast, scalable probabilistic record linkage to R. It
implements the Fellegi-Sunter model to identify and link duplicate or
related records across datasets that lack a shared unique identifier.
Model parameters are estimated via unsupervised
Expectation-Maximisation, so no labelled training data is required. A
rich library of comparison functions — from exact matching through
Jaro-Winkler, Levenshtein, date differences, and geographic distance —
lets you tailor the linkage model to your data. Multiple SQL backends
are supported through DBI, so the same code runs on SQLite, DuckDB, or
PostgreSQL.

`irelink` is a translation of the Python
[splink](https://github.com/moj-analytical-services/splink) library into
idiomatic R.

## Installation

You can install the development version of `irelink` like so:

``` r
pak::pak('christopherkenny/irelink')
```

## Example

Start by loading a demo dataset and connecting to a SQL backend.

``` r
library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months

df <- il_demo("fake_20")
con <- DBI::dbConnect(duckdb::duckdb())
```

Define an `il_spec` with comparison functions and blocking rules, then
train:

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)

model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
```

Score candidate pairs above a match-probability threshold, then cluster
into entities:

``` r
pairs <- predict(model, threshold = 0.5)
pairs
#> # A tibble: 11 × 7
#>    unique_id_l unique_id_r match_weight match_probability gamma_first_name
#>  *       <int>       <int>        <dbl>             <dbl>            <int>
#>  1           3          13         9.20             0.969                1
#>  2           5          15         9.20             0.969                1
#>  3           7          17         9.20             0.969                1
#>  4           2          11         9.20             0.969                1
#>  5           3           4         9.20             0.969                1
#>  6           4          13         9.20             0.969                1
#>  7           9          19         9.20             0.969                1
#>  8           5           6         9.20             0.969                1
#>  9           1           2         9.20             0.969                1
#> 10           1          11         9.20             0.969                1
#> 11           6          15         9.20             0.969                1
#> # ℹ 2 more variables: gamma_surname <int>, gamma_dob <int>

clusters <- il_cluster(pairs)
clusters
#> # A tibble: 13 × 2
#>    unique_id cluster_id
#>    <chr>     <chr>     
#>  1 3         cluster_1 
#>  2 5         cluster_2 
#>  3 7         cluster_3 
#>  4 2         cluster_4 
#>  5 4         cluster_1 
#>  6 9         cluster_5 
#>  7 1         cluster_4 
#>  8 6         cluster_2 
#>  9 13        cluster_1 
#> 10 15        cluster_2 
#> 11 17        cluster_3 
#> 12 11        cluster_4 
#> 13 19        cluster_5
```

Finally, drop the temporary tables and close the connection:

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
