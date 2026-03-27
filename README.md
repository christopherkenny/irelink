
<!-- README.md is generated from README.Rmd. Please edit that file -->

# irelink

<!-- badges: start -->

<!-- badges: end -->

`irelink` brings fast, scalable probabilistic record linkage to R. It
implements the Fellegi-Sunter model to identify and link duplicate or
related records across datasets that lack a shared unique identifier.
Model parameters are estimated via unsupervised
Expectation-Maximisation, so no labelled training data is required. A
rich library of comparison functions — from exact matching through
Jaro-Winkler, Levenshtein, date differences, and geographic distance —
lets you tailor the linkage model to your data. Multiple SQL backends
are supported through DBI, so the same code runs on DuckDB
(laptop-scale), SQLite, PostgreSQL, or Spark.

`irelink` is a translation of the Python
[splink](https://github.com/moj-analytical-services/splink) library into
idiomatic R.

## Installation

You can install the development version of `irelink` like so:

``` r
pak::pak('christopherkenny/irelink')
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months
## basic example code
```
