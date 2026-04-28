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
#> EM trained: first_name and dob | skipped (blocked on):
#> surname
```

You can inspect the learned parameters at any time:

``` r
il_weights(model)
#> # A tibble: 8 × 5
#>   comparison gamma_level m_prob u_prob weight
#>   <chr>            <int>  <dbl>  <dbl>  <dbl>
#> 1 first_name           0 0.0114 0.832  -6.18 
#> 2 first_name           1 0.196  0.0632  1.63 
#> 3 first_name           2 0.792  0.105   2.91 
#> 4 surname              0 0.05   0.821  -4.04 
#> 5 surname              1 0.05   0.0368  0.441
#> 6 surname              2 0.9    0.142   2.66 
#> 7 dob                  0 0.280  0.921  -1.72 
#> 8 dob                  1 0.720  0.0789  3.19
```

## Step 4: Predict

[`predict()`](https://rdrr.io/r/stats/predict.html) scores every
candidate pair and returns those above a match-probability threshold:

``` r
pairs <- predict(model, threshold = 0.5)
head(pairs)
#> # A tibble: 6 × 8
#>   unique_id_l unique_id_r gamma_first_name gamma_surname gamma_dob match_weight
#>         <int>       <int>            <int>         <int>     <int>        <dbl>
#> 1           2          12                2             1         0         1.64
#> 2           2          11                2             2         1         8.76
#> 3           3          14                2             2         0         3.86
#> 4           4          14                2             2         0         3.86
#> 5           7          17                2             2         1         8.76
#> 6          13          14                2             2         0         3.86
#> # ℹ 2 more variables: total_match_weight <dbl>, match_probability <dbl>
```

Each row is a candidate pair with columns for the left and right record
identifiers, the per-comparison gamma values, the evidence-only
`match_weight`, the prior-inclusive `total_match_weight`, and the
posterior `match_probability`.

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
#> 1 3         cluster_13
#> 2 14        cluster_13
#> 3 5         cluster_15
#> 4 6         cluster_15
#> 5 17        cluster_17
#> 6 15        cluster_15
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
| [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)                     | Date fields                   |
| [`cl_time_diff()`](http://christophertkenny.com/irelink/reference/cl_time_diff.md)                     | Time fields                   |
| [`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md)                 | Geographic coordinates        |
| [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md)         | Array or set overlap          |

For common field types, domain-specific helpers compose multiple levels
into a single call:

| Helper                                                                                           | Fields                                      |
|--------------------------------------------------------------------------------------------------|---------------------------------------------|
| [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md)                         | Generic name field                          |
| [`cl_first_last_name()`](http://christophertkenny.com/irelink/reference/cl_first_last_name.md)   | First name and last name as separate fields |
| [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md) | Forename and surname with transposition     |
| [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md)                           | Date of birth                               |
| [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md)                       | Email addresses                             |
| [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md)                 | UK postal codes                             |
| [`cl_zip_code()`](http://christophertkenny.com/irelink/reference/cl_zip_code.md)                 | US ZIP codes                                |

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

When you are done, release the model-owned database resources. In an
interactive session with abandoned models, use `il_cleanup_all(con)`
before disconnecting to drop every `irelink` table on the connection.

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
