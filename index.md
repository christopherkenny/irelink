# irelink

`irelink` brings fast, scalable probabilistic record linkage to R. It
implements the Fellegi-Sunter model to identify and link duplicate or
related records across datasets that lack a shared unique identifier.
Model parameters are estimated via unsupervised
Expectation-Maximization, so no labeled training data is required.
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

Find duplicate records within a single dataset. The bundled `fake_20`
dataset provides a small example for experimentation. `irelink` pushes
data into a SQL database for efficient pair generation, so you need a
DBI connection. Here we use an in-memory DuckDB instance.

``` r

library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months

df <- fake_20
con <- DBI::dbConnect(duckdb::duckdb())
```

An `il_spec` describes the linkage model: which fields to compare, how
to compare them, and which blocking rules to apply. Blocking rules
restrict which record pairs are generated. Only pairs that share a
surname or first name are scored, keeping computation manageable.
[`il_estimate_u()`](http://christophertkenny.com/irelink/reference/il_estimate_u.md)
estimates parameters for non-matching pairs via random sampling, and
[`il_estimate_em()`](http://christophertkenny.com/irelink/reference/il_estimate_em.md)
refines the match-weight parameters using Expectation-Maximization.

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
#> EM trained: first_name and dob | skipped (blocked on): surname
```

[`predict()`](https://rdrr.io/r/stats/predict.html) scores all candidate
pairs and returns those above the match-probability threshold. The
returned `match_weight` is the evidence-only log2 Bayes factor;
`total_match_weight` adds the prior odds used to compute
`match_probability`.
[`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
groups the matched pairs into deduplicated entities.

``` r

pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)
clusters
#> # A tibble: 18 × 2
#>    unique_id cluster_id
#>    <chr>     <chr>     
#>  1 10        cluster_10
#>  2 6         cluster_15
#>  3 3         cluster_13
#>  4 13        cluster_13
#>  5 7         cluster_17
#>  6 15        cluster_15
#>  7 8         cluster_17
#>  8 19        cluster_10
#>  9 5         cluster_15
#> 10 4         cluster_13
#> 11 17        cluster_17
#> 12 14        cluster_13
#> 13 20        cluster_10
#> 14 9         cluster_10
#> 15 2         cluster_1 
#> 16 11        cluster_1 
#> 17 1         cluster_1 
#> 18 12        cluster_1
```

[`il_cleanup()`](http://christophertkenny.com/irelink/reference/il_cleanup.md)
drops the temporary tables owned by this model. Use
`il_cleanup_all(con)` as an interactive escape hatch when a failed or
exploratory session may have left several `irelink` models’ tables
behind.

``` r

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

## Linking

Link records across two separate datasets, finding which rows in one
table correspond to rows in the other. The FEBRL benchmark datasets
provide a classic record-linkage scenario: `febrl4a` contains 5,000
original records and `febrl4b` contains one duplicate per original with
realistic data-quality errors.

``` r

# Use a small slice for this quick demo; see vignette("record-linkage") for the full workflow
df_a <- head(febrl4a, 200)
df_b <- head(febrl4b, 200)

con <- DBI::dbConnect(duckdb::duckdb())
```

The spec is the same as for deduplication. Pass both data frames to
[`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
and set `link_type = "link"` to tell the model to score only
cross-dataset pairs, not pairs within the same dataset.

``` r

spec <- il_spec() |>
  il_compare(given_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(date_of_birth, cl_exact()) |>
  il_block_on(surname)

model <- il_model(
  df_a,
  df_b,
  spec = spec,
  con = con,
  link_type = "link"
)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
#> EM trained: given_name and date_of_birth | skipped (blocked on): surname
```

Each row in the result is a candidate match between a record in `df_a`
and a record in `df_b`, scored by match probability.

``` r

pairs <- predict(model, threshold = 0.5)
pairs
#> # A tibble: 3 × 8
#>   unique_id_l unique_id_r gamma_given_name gamma_surname gamma_date_of_birth
#> *       <int>       <int>            <int>         <int>               <int>
#> 1         165          59                0             2                   1
#> 2          29          77                0             2                   1
#> 3          24         160                0             2                   1
#> # ℹ 3 more variables: match_weight <dbl>, total_match_weight <dbl>,
#> #   match_probability <dbl>
```

As in the prior example,
[`il_cleanup()`](http://christophertkenny.com/irelink/reference/il_cleanup.md)
drops this model’s temporary tables.

``` r

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
