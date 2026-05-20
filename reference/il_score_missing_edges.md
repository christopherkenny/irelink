# Score Missing Edges Within Clusters

Identifies pairs of records within the same cluster that were not
already scored during prediction (e.g. because they were in different
blocking groups), and scores them using the model. This can reveal
low-confidence links that bridge otherwise separate sub-clusters.

## Usage

``` r
il_score_missing_edges(model, pairs, clusters, threshold = 0)
```

## Arguments

- model:

  A trained `il_model` object.

- pairs:

  An `il_compared` tibble from
  [`predict.il_model()`](http://christophertkenny.com/irelink/reference/predict.il_model.md).

- clusters:

  A tibble from
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
  with columns `unique_id` and `cluster_id`.

- threshold:

  Numeric match-probability threshold for returned pairs. Defaults to
  `0`.

## Value

An `il_compared` tibble of newly scored pairs (those not already in
`pairs`).

## Examples

``` r
df <- data.frame(
  unique_id = c(1, 2, 3),
  first_name = c('John', 'John', 'Jon'),
  surname = c('Smith', 'Smyth', 'Smith')
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_exact()) |>
  il_compare(surname, cl_exact()) |>
  il_block_on(surname)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
#> EM trained: first_name | skipped (blocked on): surname
pairs <- predict(model, threshold = 0.01)
clusters <- tibble::tibble(
  unique_id = c('1', '2', '3'),
  cluster_id = 'cluster_1'
)
missing <- il_score_missing_edges(model, pairs, clusters)
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
