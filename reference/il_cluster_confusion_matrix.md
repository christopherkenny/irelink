# Cluster-Level Confusion Matrix for Deduplication

Computes a record-level confusion matrix after clustering predicted
matches into entities. This mirrors the common `dedupe.ids` style of
evaluation used in fastLink comparisons: a record is treated as
"duplicated" if it is not the first record in its predicted cluster, and
likewise for the ground-truth `labels_col`.

## Usage

``` r
il_cluster_confusion_matrix(
  model,
  labels_col,
  threshold = 0.85,
  method = c("connected", "best_link"),
  ties_method = c("lowest_id", "drop"),
  source_dataset = NULL
)
```

## Arguments

- model:

  A trained `il_model` object for a deduplication task.

- labels_col:

  String naming the ground-truth cluster/entity column in the model's
  source data.

- threshold:

  Match-probability threshold passed to
  [`predict()`](https://rdrr.io/r/stats/predict.html). Defaults to
  `0.85`.

- method:

  Clustering method passed to
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md).

- ties_method:

  Tie handling for `method = "best_link"`, passed to
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md).

- source_dataset:

  Optional source-dataset mapping passed to
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md).

## Value

A one-row tibble with columns `threshold`, `tp`, `fp`, `fn`, `tn`,
`precision`, `recall`, and `f1`.

## Details

For DuckDB and PostgreSQL backends, pair scoring and clustering are
pushed into SQL where possible. The final summary still returns a
one-row tibble in R.

## Examples

``` r
df <- data.frame(
  unique_id = 1:5,
  first_name = c('John', 'John', 'Mary', 'Bob', 'Bob'),
  surname = c('Smith', 'Smith', 'Jones', 'Brown', 'Brown'),
  cluster = c(1, 1, 2, 3, 4)
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_exact()) |>
  il_compare(surname, cl_exact()) |>
  il_block_on(surname)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
#> Warning: Comparisons surname overlap with the EM blocking rule and will not be updated
#> in this pass.
#> ℹ These columns have no variation within the blocked training pairs, so their
#>   m/u parameters cannot be estimated from this run.
#> ℹ If these comparisons are important for scoring, this can lead to poor
#>   calibration or over-confident match probabilities.
#> ℹ Use a different EM blocking rule, add another EM pass on non-overlapping
#>   fields, or raise the prediction threshold and inspect the results carefully.

il_cluster_confusion_matrix(model, labels_col = 'cluster', threshold = 0.85)
#> # A tibble: 1 × 9
#>   threshold    tp    fp    fn    tn fn_blocking_miss precision recall    f1
#>       <dbl> <int> <int> <int> <int>            <int>     <dbl>  <dbl> <dbl>
#> 1      0.85     1     1     0     3               NA       0.5      1 0.667
DBI::dbDisconnect(con, shutdown = TRUE)
```
