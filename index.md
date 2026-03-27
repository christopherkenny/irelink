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

A typical linkage workflow defines comparisons, trains a model, predicts
matches, and clusters results:

``` r
library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months

df <- il_demo("fake_20")
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")

# Define how to compare records
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)

# Build and train the model
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))

# Predict and cluster
pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)
head(clusters)
#> # A tibble: 6 × 2
#>   unique_id cluster_id
#>   <chr>     <chr>     
#> 1 1         cluster_1 
#> 2 2         cluster_1 
#> 3 3         cluster_2 
#> 4 4         cluster_2 
#> 5 5         cluster_3 
#> 6 6         cluster_3

# Clean up
il_cleanup(model)
DBI::dbDisconnect(con)
```
