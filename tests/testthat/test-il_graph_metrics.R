# Sprint 9 — Graph metrics: il_graph_metrics()
# Translated from: test_graph_metrics.py

test_that("il_graph_metrics() returns a list of three tibbles", {
  skip_if_sprint_lt(9)

  # From: test_size_density_dedupe — simple 3-record example
  pairs <- tibble::tibble(
    unique_id_l = c("2"),
    unique_id_r = c("3"),
    match_probability = c(0.95),
    match_weight = c(4.25),
    cluster_id = c("cluster_1")
  )

  clusters <- tibble::tibble(
    unique_id = c("1", "2", "3"),
    cluster_id = c("cluster_0", "cluster_1", "cluster_1")
  )

  metrics <- il_graph_metrics(pairs, clusters)

  expect_type(metrics, "list")
  expect_true("nodes" %in% names(metrics))
  expect_true("edges" %in% names(metrics))
  expect_true("clusters" %in% names(metrics))
  expect_s3_class(metrics$nodes, "tbl_df")
  expect_s3_class(metrics$edges, "tbl_df")
  expect_s3_class(metrics$clusters, "tbl_df")
})

test_that("il_graph_metrics() computes correct cluster sizes", {
  skip_if_sprint_lt(9)

  # From: test_metrics — known cluster structure
  # Cluster A: 4 nodes, 4 edges
  # Cluster B: 2 nodes, 1 edge
  # Cluster C: 1 node (isolated)
  pairs <- tibble::tibble(
    unique_id_l = c("1", "1", "2", "3", "5"),
    unique_id_r = c("2", "3", "3", "4", "6"),
    match_probability = rep(0.95, 5),
    match_weight = rep(4.25, 5)
  )

  clusters <- tibble::tibble(
    unique_id = c("1", "2", "3", "4", "5", "6", "7"),
    cluster_id = c("A", "A", "A", "A", "B", "B", "C")
  )

  metrics <- il_graph_metrics(pairs, clusters)

  cluster_a <- metrics$clusters[metrics$clusters$cluster_id == "A", ]
  cluster_b <- metrics$clusters[metrics$clusters$cluster_id == "B", ]
  cluster_c <- metrics$clusters[metrics$clusters$cluster_id == "C", ]

  expect_equal(cluster_a$n_nodes, 4)
  expect_equal(cluster_b$n_nodes, 2)
  expect_equal(cluster_c$n_nodes, 1)
})

test_that("il_graph_metrics() computes node degree", {
  skip_if_sprint_lt(9)

  pairs <- tibble::tibble(
    unique_id_l = c("1", "1", "2"),
    unique_id_r = c("2", "3", "3"),
    match_probability = rep(0.95, 3),
    match_weight = rep(4.25, 3)
  )

  clusters <- tibble::tibble(
    unique_id = c("1", "2", "3"),
    cluster_id = rep("A", 3)
  )

  metrics <- il_graph_metrics(pairs, clusters)

  # Node 1 connects to 2 and 3 → degree 2
  node_1 <- metrics$nodes[metrics$nodes$unique_id == "1", ]
  expect_equal(node_1$degree, 2)

  # Node 2 connects to 1 and 3 → degree 2
  node_2 <- metrics$nodes[metrics$nodes$unique_id == "2", ]
  expect_equal(node_2$degree, 2)
})

test_that("il_graph_metrics() identifies isolated nodes", {
  skip_if_sprint_lt(9)

  pairs <- tibble::tibble(
    unique_id_l = c("1"),
    unique_id_r = c("2"),
    match_probability = 0.95,
    match_weight = 4.25
  )

  clusters <- tibble::tibble(
    unique_id = c("1", "2", "3"),
    cluster_id = c("A", "A", "B")
  )

  metrics <- il_graph_metrics(pairs, clusters)

  # Node 3 is isolated → degree 0
  node_3 <- metrics$nodes[metrics$nodes$unique_id == "3", ]
  expect_equal(node_3$degree, 0)
})

test_that("il_graph_metrics() computes cluster density", {
  skip_if_sprint_lt(9)

  # From: test_size_density_dedupe — 2 nodes, 1 edge → density = 1.0
  pairs <- tibble::tibble(
    unique_id_l = c("1"),
    unique_id_r = c("2"),
    match_probability = 0.95,
    match_weight = 4.25
  )

  clusters <- tibble::tibble(
    unique_id = c("1", "2"),
    cluster_id = c("A", "A")
  )

  metrics <- il_graph_metrics(pairs, clusters)

  # 2 nodes, 1 edge, max edges = C(2,2) = 1 → density = 1.0
  cluster_a <- metrics$clusters[metrics$clusters$cluster_id == "A", ]
  expect_equal(cluster_a$density, 1.0, tolerance = 0.01)
})
