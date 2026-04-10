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
if (FALSE) { # \dontrun{
pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)
missing <- il_score_missing_edges(model, pairs, clusters)
} # }
```
