# Deduplicating 50k Synthetic Records

This vignette replicates the [Splink “Deduplicate 50k synthetic”
demo](https://moj-analytical-services.github.io/splink/demos/examples/duckdb/deduplicate_50k_synthetic.html)
using `irelink`. The data is based on historical persons scraped from
Wikidata, with duplicate records introduced alongside a variety of
realistic errors (typos, missing values, swapped fields). The `cluster`
column provides ground-truth entity labels for evaluation.

This vignette requires the
[nanoparquet](https://cran.r-project.org/package=nanoparquet) package to
read the remote Parquet file and will only compile when the package and
data URL are both available.

## Load the data

``` r
library(irelink)
library(ggplot2)

df
```

## Profile the data

Profile completeness and value distributions to inform blocking and
comparison choices:

``` r
con <- DBI::dbConnect(duckdb::duckdb())
```

``` r
df |>
  il_completeness(con = con) |>
  autoplot()
```

``` r
il_profile(df, first_name, surname, dob, birth_place, con = con, top_n = 8)
```

## Choose blocking rules

``` r
il_suggest_blocking(df, con = con)
```

The `cumulative_pairs` column shows the total unique pairs across all
rules so far:

``` r
il_count_pairs(
  df,
  block_on(surname, dob),
  block_on(first_name, dob),
  block_on(first_name, surname),
  block_on(dob, birth_place),
  con = con
)
```

## Define the specification

Term-frequency adjustment is applied to `birth_place` and `occupation`
so common values (e.g., “London”) receive less weight than rare ones:

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_dob()) |>
  il_compare(postcode_fake, cl_postcode()) |>
  il_compare(birth_place, cl_exact(term_frequency = TRUE)) |>
  il_compare(occupation, cl_exact(term_frequency = TRUE)) |>
  il_block_on(surname, dob) |>
  il_block_on(first_name, dob) |>
  il_block_on(first_name, surname) |>
  il_block_on(dob, birth_place)

spec
```

## Train the model

``` r
model <- df |>
  il_model(spec = spec, con = con) |>
  il_estimate_prior(
    block_on(first_name, surname, dob),
    block_on(dob, postcode_fake),
    recall = 0.6
  ) |>
  il_estimate_u(max_pairs = 5e6) |>
  il_estimate_em(block_on(first_name, surname)) |>
  il_estimate_em(block_on(dob))
```

## Inspect the trained model

``` r
summary(model)
```

``` r
autoplot(model)
```

``` r
autoplot(model, type = 'parameters')
```

``` r
autoplot(il_unlinkables(model))
```

## Predict

``` r
predictions <- predict(model, threshold = 0.5)
predictions
```

``` r
autoplot(predictions)
```

``` r
autoplot(predictions, which = 1)
```

## Cluster

``` r
clusters <- il_cluster(predictions, threshold = 0.95)
clusters
```

## Evaluate against ground truth

``` r
acc <- il_accuracy(model, labels_col = 'cluster')
acc
```

``` r
autoplot(acc)
```

``` r
autoplot(il_roc(model, labels_col = 'cluster'))
```

``` r
autoplot(il_precision_recall(model, labels_col = 'cluster'))
```

### Error inspection

``` r
errors <- il_errors(model, labels_col = 'cluster', threshold = 0.999)
errors[errors$error_type == 'false_positive', ]
```

Some false negatives will be because the true pair was never generated
by any blocking rule:

``` r
errors <- il_errors(model, labels_col = 'cluster', threshold = 0.5)
errors[errors$error_type == 'false_negative', ]
```

## Cleanup

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
