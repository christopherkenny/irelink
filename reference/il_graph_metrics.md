# Compute Graph Metrics for Clusters

Returns node-, edge-, and cluster-level metrics from the linkage graph.
Useful for diagnosing cluster quality and identifying bridge edges or
weakly connected components.

## Usage

``` r
il_graph_metrics(pairs, clusters)
```

## Arguments

- pairs:

  An `il_compared` tibble from
  [`predict.il_model()`](http://christophertkenny.com/irelink/reference/predict.il_model.md).

- clusters:

  A tibble from
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
  with cluster assignments.

## Value

A named list of three tibbles:

- `nodes`:

  Record-level metrics (degree, centrality).

- `edges`:

  Edge-level metrics (match probability, bridge flag).

- `clusters`:

  Cluster-level metrics (size, density).

## Examples

``` r
df <- data.frame(
  unique_id = 1:20,
  first_name = c(
    'John', 'Jon', 'Jane', 'Jane', 'Bob',
    'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
    'John', 'Jon', 'Jane', 'Janet', 'Bob',
    'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
  ),
  surname = c(
    'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Brown', 'White', 'White',
    'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Browne', 'White', 'White'
  ),
  dob = c(
    '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
    '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
    '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
    '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
    '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
  ),
  city = c(
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
  ),
  email = c(
    'john@example.com', 'jon@example.com', 'jane@example.com',
    'jane@example.com', 'bob@example.com', 'bobby@example.com',
    'alice@example.com', 'alicia@example.com', 'tom@example.com',
    'thomas@example.com', 'john@example.com', 'jon@example.com',
    'jane@example.com', 'janet@example.com', 'bob@example.com',
    'robert@example.com', 'alice@example.com', 'alison@example.com',
    'tom@example.com', 'tomas@example.com'
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))
pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)

metrics <- il_graph_metrics(pairs, clusters)
metrics$clusters
#> # A tibble: 5 × 4
#>   cluster_id n_nodes n_edges density
#>   <chr>        <int>   <int>   <dbl>
#> 1 cluster_13       3       3       1
#> 2 cluster_10       3       3       1
#> 3 cluster_15       3       3       1
#> 4 cluster_17       3       3       1
#> 5 cluster_1        3       3       1
DBI::dbDisconnect(con, shutdown = TRUE)
```
