# Sprint 9 — Graph metrics: il_graph_metrics()
# Translated from: test_graph_metrics.py

test_that('il_graph_metrics() returns a list of three tibbles', {
  # From: test_size_density_dedupe — simple 3-record example
  pairs <- tibble::tibble(
    unique_id_l = c('2'),
    unique_id_r = c('3'),
    match_probability = c(0.95),
    match_weight = c(4.25),
    cluster_id = c('cluster_1')
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = c('cluster_0', 'cluster_1', 'cluster_1')
  )

  metrics <- il_graph_metrics(pairs, clusters)

  expect_type(metrics, 'list')
  expect_true('nodes' %in% names(metrics))
  expect_true('edges' %in% names(metrics))
  expect_true('clusters' %in% names(metrics))
  expect_s3_class(metrics$nodes, 'tbl_df')
  expect_s3_class(metrics$edges, 'tbl_df')
  expect_s3_class(metrics$clusters, 'tbl_df')
})

test_that('il_graph_metrics() computes correct cluster sizes', {
  # From: test_metrics — known cluster structure
  # Cluster A: 4 nodes, 4 edges
  # Cluster B: 2 nodes, 1 edge
  # Cluster C: 1 node (isolated)
  pairs <- tibble::tibble(
    unique_id_l = c('1', '1', '2', '3', '5'),
    unique_id_r = c('2', '3', '3', '4', '6'),
    match_probability = rep(0.95, 5),
    match_weight = rep(4.25, 5)
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3', '4', '5', '6', '7'),
    cluster_id = c('A', 'A', 'A', 'A', 'B', 'B', 'C')
  )

  metrics <- il_graph_metrics(pairs, clusters)

  cluster_a <- metrics$clusters[metrics$clusters$cluster_id == 'A', ]
  cluster_b <- metrics$clusters[metrics$clusters$cluster_id == 'B', ]
  cluster_c <- metrics$clusters[metrics$clusters$cluster_id == 'C', ]

  expect_equal(cluster_a$n_nodes, 4)
  expect_equal(cluster_b$n_nodes, 2)
  expect_equal(cluster_c$n_nodes, 1)
})

test_that('il_graph_metrics() computes node degree', {
  pairs <- tibble::tibble(
    unique_id_l = c('1', '1', '2'),
    unique_id_r = c('2', '3', '3'),
    match_probability = rep(0.95, 3),
    match_weight = rep(4.25, 3)
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('A', 3)
  )

  metrics <- il_graph_metrics(pairs, clusters)

  # Node 1 connects to 2 and 3 → degree 2
  node_1 <- metrics$nodes[metrics$nodes$unique_id == '1', ]
  expect_equal(node_1$degree, 2)

  # Node 2 connects to 1 and 3 → degree 2
  node_2 <- metrics$nodes[metrics$nodes$unique_id == '2', ]
  expect_equal(node_2$degree, 2)
})

test_that('il_graph_metrics() identifies isolated nodes', {
  pairs <- tibble::tibble(
    unique_id_l = c('1'),
    unique_id_r = c('2'),
    match_probability = 0.95,
    match_weight = 4.25
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = c('A', 'A', 'B')
  )

  metrics <- il_graph_metrics(pairs, clusters)

  # Node 3 is isolated → degree 0
  node_3 <- metrics$nodes[metrics$nodes$unique_id == '3', ]
  expect_equal(node_3$degree, 0)
})

test_that('il_graph_metrics() computes cluster density', {
  # From: test_size_density_dedupe — 2 nodes, 1 edge → density = 1.0
  pairs <- tibble::tibble(
    unique_id_l = c('1'),
    unique_id_r = c('2'),
    match_probability = 0.95,
    match_weight = 4.25
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2'),
    cluster_id = c('A', 'A')
  )

  metrics <- il_graph_metrics(pairs, clusters)

  # 2 nodes, 1 edge, max edges = C(2,2) = 1 → density = 1.0
  cluster_a <- metrics$clusters[metrics$clusters$cluster_id == 'A', ]
  expect_equal(cluster_a$density, 1.0, tolerance = 0.01)
})

test_that('il_graph_metrics() edges tibble contains is_bridge column', {
  pairs <- tibble::tibble(
    unique_id_l = c('1'),
    unique_id_r = c('2'),
    match_probability = 0.95,
    match_weight = 4.25
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2'),
    cluster_id = c('A', 'A')
  )

  metrics <- il_graph_metrics(pairs, clusters)
  expect_true('is_bridge' %in% names(metrics$edges))
  expect_type(metrics$edges$is_bridge, 'logical')
})

test_that('il_graph_metrics() identifies bridge edges correctly', {
  # Chain: 1-2-3 (edges 1-2 and 2-3 are both bridges)
  pairs <- tibble::tibble(
    unique_id_l = c('1', '2'),
    unique_id_r = c('2', '3'),
    match_probability = c(0.95, 0.90),
    match_weight = c(4.25, 3.5)
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('A', 3)
  )

  metrics <- il_graph_metrics(pairs, clusters)
  expect_true(all(metrics$edges$is_bridge))
})

test_that('il_graph_metrics() non-bridges in fully connected cluster', {
  # Triangle: 1-2, 2-3, 1-3 — no bridges
  pairs <- tibble::tibble(
    unique_id_l = c('1', '2', '1'),
    unique_id_r = c('2', '3', '3'),
    match_probability = rep(0.95, 3),
    match_weight = rep(4.25, 3)
  )

  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('A', 3)
  )

  metrics <- il_graph_metrics(pairs, clusters)
  expect_true(!any(metrics$edges$is_bridge))
})

test_that('il_graph_metrics() computes node centrality', {
  # Star: 1 connects to 2, 3, 4 — node 1 has degree 3, centrality 1.0
  pairs <- tibble::tibble(
    unique_id_l = c('1', '1', '1'),
    unique_id_r = c('2', '3', '4'),
    match_probability = rep(0.9, 3),
    match_weight = rep(3.0, 3)
  )
  clusters <- tibble::tibble(
    unique_id = as.character(1:4),
    cluster_id = rep('A', 4)
  )

  metrics <- il_graph_metrics(pairs, clusters)
  expect_true('node_centrality' %in% names(metrics$nodes))

  hub <- metrics$nodes[metrics$nodes$unique_id == '1', ]
  # degree 3, cluster_size 4, centrality = 3/(4-1) = 1.0
  expect_equal(hub$node_centrality, 1.0, tolerance = 0.01)

  leaf <- metrics$nodes[metrics$nodes$unique_id == '2', ]
  # degree 1, centrality = 1/3
  expect_equal(leaf$node_centrality, 1 / 3, tolerance = 0.01)
})

test_that('il_graph_metrics() includes cluster_centralisation', {
  # Triangle: fully connected — all nodes degree 2 — centralisation = 0
  pairs <- tibble::tibble(
    unique_id_l = c('1', '2', '1'),
    unique_id_r = c('2', '3', '3'),
    match_probability = rep(0.95, 3),
    match_weight = rep(4.25, 3)
  )
  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('A', 3)
  )

  metrics <- il_graph_metrics(pairs, clusters)
  expect_true('cluster_centralisation' %in% names(metrics$clusters))
  # 3 nodes, all degree 2 → (3*2 - 6) / (2*1) = 0
  expect_equal(metrics$clusters$cluster_centralisation, 0, tolerance = 0.01)
})

test_that('il_graph_metrics() validates pair and cluster columns', {
  pairs <- tibble::tibble(
    unique_id_l = c('1'),
    unique_id_r = c('2'),
    match_probability = 0.95,
    match_weight = 4.25
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))
  clusters <- tibble::tibble(
    unique_id = c('1', '2'),
    cluster_id = c('A', 'A')
  )

  expect_error(
    il_graph_metrics(pairs[, c('unique_id_l', 'unique_id_r', 'match_probability')], clusters),
    'match_weight'
  )
  expect_error(
    il_graph_metrics(pairs, clusters[, 'unique_id', drop = FALSE]),
    'cluster_id'
  )
  expect_error(
    il_graph_metrics(
      pairs,
      tibble::tibble(unique_id = c('1', '1'), cluster_id = c('A', 'A'))
    ),
    'one row per'
  )
})
