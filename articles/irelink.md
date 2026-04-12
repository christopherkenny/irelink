# Getting Started

## What is record linkage?

Record linkage (also called entity resolution or deduplication) is the
task of identifying records in one or more datasets that refer to the
same real-world entity. When datasets lack a shared unique identifier,
you must rely on imperfect fields like names, dates of birth, and
addresses to decide which rows belong together. Probabilistic record
linkage formalises this by estimating the likelihood that two records
are a match given how similar they are across multiple fields.

`irelink` implements the Fellegi-Sunter model of probabilistic record
linkage. Parameters are estimated via unsupervised
Expectation-Maximisation, so no labelled training data is required to
get started.

## A typical workflow

Every linkage task follows the same general pattern:

1.  **Define a specification** — choose which columns to compare and
    how.
2.  **Build a model** — load data into a SQL backend and attach the
    specification.
3.  **Train parameters** — estimate u-probabilities, then run EM to
    learn m-probabilities.
4.  **Predict** — score every candidate pair and threshold to get likely
    matches.
5.  **Cluster** — resolve pairwise links into groups of records that
    represent the same entity.

The example below walks through each step using a small built-in
dataset.

## Step 1: Define a specification

A specification describes the comparisons and blocking rules that drive
the model. Comparisons tell `irelink` how to score similarity on each
field. Blocking rules limit which record pairs are compared, making
linkage tractable on large data.

``` r
library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months

spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)

spec
#> Linkage Specification
#>   Comparisons (3):
#>     first_name : jaro_winkler
#>     surname : jaro_winkler
#>     dob : exact
#>   Blocking rules (2, OR-ed):
#>     1. surname
#>     2. first_name
```

Each call to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
adds a comparison dimension. `cl_jaro_winkler(0.9, 0.7)` means: score a
pair as level 2 if Jaro-Winkler similarity is at least 0.9, level 1 if
at least 0.7, and level 0 otherwise.
[`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md)
is a simple binary match.

Blocking rules defined with
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
restrict candidate pairs to records that share the same value in the
blocking column. Multiple blocking rules are combined with OR logic, so
a pair is compared if it satisfies any rule.

## Step 2: Build a model

[`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
uploads the data to a SQL backend and attaches the specification. Any
DBI-compatible connection works. Here we use an in-memory DuckDB
database:

``` r
df <- fake_20
con <- DBI::dbConnect(duckdb::duckdb())

model <- il_model(df, spec = spec, con = con)
model
#> irelink Model
#>   Status: Untrained
#>   Link type: dedupe
#>   Records: 20
#>   Comparisons: 3
#>   Blocking rules: 2
```

## Step 3: Train parameters

Training is a two-step process. First, estimate u-probabilities (the
chance two random non-matching records agree on each comparison level)
from a random sample of pairs:

``` r
model <- il_estimate_u(model)
```

Then run Expectation-Maximisation to learn m-probabilities (the chance
true matches agree on each level). You supply a blocking rule to
generate the training pairs:

``` r
model <- il_estimate_em(model, block_on(surname))
```

You can inspect the learned parameters at any time:

``` r
il_weights(model)
#> # A tibble: 8 × 5
#>   comparison gamma_level m_prob u_prob weight
#>   <chr>            <int>  <dbl>  <dbl>  <dbl>
#> 1 first_name           0 0.0104 0.832   -6.32
#> 2 first_name           1 0.244  0.0632   1.95
#> 3 first_name           2 0.746  0.105    2.82
#> 4 surname              0 0.0103 0.821   -6.31
#> 5 surname              1 0.0103 0.0368  -1.83
#> 6 surname              2 0.979  0.142    2.78
#> 7 dob                  0 0.0908 0.921   -3.34
#> 8 dob                  1 0.909  0.0789   3.53
```

## Step 4: Predict

[`predict()`](https://rdrr.io/r/stats/predict.html) scores every
candidate pair and returns those above a match-weight threshold:

``` r
pairs <- predict(model, threshold = 0.5)
head(pairs)
#> # A tibble: 6 × 7
#>   unique_id_l unique_id_r match_weight match_probability gamma_first_name
#>         <int>       <int>        <dbl>             <dbl>            <int>
#> 1           5          15         9.13             0.967                2
#> 2           7          17         9.13             0.967                2
#> 3           3           4         9.13             0.967                2
#> 4           2          11         9.13             0.967                2
#> 5           1           2         9.13             0.967                2
#> 6           6          15         9.13             0.967                2
#> # ℹ 2 more variables: gamma_surname <int>, gamma_dob <int>
```

Each row is a candidate pair with columns for the left and right record
identifiers, the per-comparison gamma values, and the overall match
weight and probability.

## Step 5: Cluster

[`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
resolves pairwise predictions into entity clusters using
connected-components analysis:

``` r
clusters <- il_cluster(pairs)
head(clusters)
#> # A tibble: 6 × 2
#>   unique_id cluster_id
#>   <chr>     <chr>     
#> 1 15        cluster_15
#> 2 17        cluster_17
#> 3 6         cluster_15
#> 4 5         cluster_15
#> 5 3         cluster_13
#> 6 19        cluster_10
```

Each record is assigned a `cluster_id`. Records sharing the same cluster
are considered to be the same entity.

## Comparison levels

`irelink` ships with a rich library of comparison levels for common
field types:

| Level                                                                                                  | Use case                      |
|--------------------------------------------------------------------------------------------------------|-------------------------------|
| [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md)                             | Binary exact match            |
| [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md)               | Names, short strings          |
| [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md)                 | General fuzzy strings         |
| [`cl_damerau_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_damerau_levenshtein.md) | Strings with transpositions   |
| [`cl_jaro()`](http://christophertkenny.com/irelink/reference/cl_jaro.md)                               | Lightweight string similarity |
| [`cl_jaccard()`](http://christophertkenny.com/irelink/reference/cl_jaccard.md)                         | Token-set overlap             |
| [`cl_cosine()`](http://christophertkenny.com/irelink/reference/cl_cosine.md)                           | Embedding similarity          |
| [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md)               | Numeric fields (e.g., age)    |
| [`cl_pct_diff()`](http://christophertkenny.com/irelink/reference/cl_pct_diff.md)                       | Percentage difference         |
| [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)                     | Date or time fields           |
| [`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md)                 | Geographic coordinates        |
| [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md)         | Array or set overlap          |

For common field types, domain-specific helpers compose multiple levels
into a single call:

| Helper                                                                                           | Fields                            |
|--------------------------------------------------------------------------------------------------|-----------------------------------|
| [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md)                         | Generic name field                |
| [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md) | First name and last name together |
| [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md)                           | Date of birth                     |
| [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md)                       | Email addresses                   |
| [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md)                 | Postal codes                      |

## Evaluation

If you have labelled data (pairs known to be matches or non-matches),
`irelink` provides tools to assess model quality:

- [`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md)
  — overall accuracy at a threshold
- [`il_precision_recall()`](http://christophertkenny.com/irelink/reference/il_precision_recall.md)
  — precision and recall across thresholds
- [`il_roc()`](http://christophertkenny.com/irelink/reference/il_roc.md)
  — ROC curve data
- [`il_errors()`](http://christophertkenny.com/irelink/reference/il_errors.md)
  — inspect false positives and false negatives

## Cleaning up

When you are done, release the database resources:

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
