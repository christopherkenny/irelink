
<!-- README.md is generated from README.Rmd. Please edit that file -->

# irelink <a href="http://christophertkenny.com/irelink/"><img src="man/figures/logo.png" align="right" height="130" alt="irelink website" /></a>

<!-- badges: start -->

<!-- badges: end -->

`irelink` brings fast, scalable probabilistic record linkage to R. It
implements the Fellegi-Sunter model to identify and link duplicate or
related records across datasets that lack a shared unique identifier.
Model parameters are estimated via unsupervised
Expectation-Maximisation, so no labelled training data is required.
Comparison functions cover exact matching, Jaro-Winkler, Levenshtein,
date differences, and geographic distance, letting you tailor the model
to your data. Multiple SQL backends are supported through DBI, so the
same code runs on SQLite, DuckDB, or PostgreSQL.

`irelink` is a translation of the Python
[splink](https://github.com/moj-analytical-services/splink) library into
idiomatic R.

## Installation

You can install the development version of `irelink` like so:

``` r
pak::pak('christopherkenny/irelink')
```

## Deduplication

Find duplicate records within a single dataset. `il_demo()` loads a
built-in synthetic dataset for experimentation. `irelink` pushes data
into a SQL database for efficient pair generation, so you need a DBI
connection. Here we use an in-memory DuckDB instance.

``` r
library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months

df <- il_demo('fake_20')
con <- DBI::dbConnect(duckdb::duckdb())
```

An `il_spec` describes the linkage model: which fields to compare, how
to compare them, and which blocking rules to apply. Blocking rules
restrict which record pairs are generated. Only pairs that share a
surname or first name are scored, keeping computation manageable.
`il_estimate_u()` estimates parameters for non-matching pairs via random
sampling, and `il_estimate_em()` refines the match-weight parameters
using Expectation-Maximisation.

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

`predict()` scores all candidate pairs and returns those above the
threshold. `il_cluster()` groups the matched pairs into deduplicated
entities.

``` r
pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)
clusters
#> # A tibble: 13 × 2
#>    unique_id cluster_id
#>    <chr>     <chr>     
#>  1 9         cluster_1 
#>  2 3         cluster_2 
#>  3 5         cluster_3 
#>  4 4         cluster_2 
#>  5 2         cluster_4 
#>  6 7         cluster_5 
#>  7 1         cluster_4 
#>  8 6         cluster_3 
#>  9 19        cluster_1 
#> 10 13        cluster_2 
#> 11 15        cluster_3 
#> 12 11        cluster_4 
#> 13 17        cluster_5
```

`il_cleanup()` drops the temporary tables that `irelink` wrote to the
database. Always call it when you’re done to avoid leaving stale tables
in your connection.

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

## Linking

Link records across two separate datasets, finding which rows in one
table correspond to rows in the other. `il_demo('fake_1000_links')`
returns a list with `df_a` and `df_b`, two halves of the same synthetic
population. Each record in one dataset has a counterpart in the other.

``` r
dfs <- il_demo('fake_1000_links')
con <- DBI::dbConnect(duckdb::duckdb())
```

The spec is the same as for deduplication. Pass both data frames to
`il_model()` and set `link_type = "link"` to tell the model to score
only cross-dataset pairs, not pairs within the same dataset.

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname)

model <- il_model(
  dfs$df_a,
  dfs$df_b,
  spec = spec,
  con = con,
  link_type = 'link'
)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
```

Each row in the result is a candidate match between a record in `df_a`
and a record in `df_b`, scored by match probability.

``` r
pairs <- predict(model, threshold = 0.5)
pairs
#> # A tibble: 7,934 × 7
#>    unique_id_l unique_id_r match_weight match_probability gamma_first_name
#>  *       <int>       <int>        <dbl>             <dbl>            <int>
#>  1          46         982         4.80             0.595                0
#>  2          59         978         4.80             0.595                0
#>  3          66         982         4.80             0.595                0
#>  4          71         925         4.80             0.595                0
#>  5          78         980         4.80             0.595                0
#>  6          88         866         4.80             0.595                0
#>  7          90         996         4.80             0.595                0
#>  8         105         992         4.80             0.595                0
#>  9         119         994         4.80             0.595                0
#> 10         133         901         4.80             0.595                0
#> # ℹ 7,924 more rows
#> # ℹ 2 more variables: gamma_surname <int>, gamma_dob <int>
```

As in the prior example, `il_cleanup()` drops the temporary tables that
`irelink` wrote to the database.

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
