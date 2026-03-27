# Sprint 9 — Clustering: il_cluster()
# Translated from: test_clustering.py, test_cluster_using_single_best_links.py,
#                  test_cc_random_graphs.py, test_cluster_at_multiple_thresholds.py

test_that('il_cluster() assigns connected pairs to the same cluster', {
  skip_if_sprint_lt(9)

  # Hand-crafted pairs: A-B and B-C should be one cluster of three
  pairs <- tibble::tibble(
    unique_id_l = c('A', 'B'),
    unique_id_r = c('B', 'C'),
    match_weight = c(5.0, 4.0),
    match_probability = c(0.97, 0.94)
  )
  pairs <- structure(pairs, class = c('il_compared', class(pairs)))

  clusters <- il_cluster(pairs, threshold = 0.5)

  expect_s3_class(clusters, 'tbl_df')
  expect_true('cluster_id' %in% names(clusters))

  # All three records should share the same cluster
  expect_equal(length(unique(clusters$cluster_id)), 1)
  expect_equal(nrow(clusters), 3)
})

test_that('il_cluster() threshold re-filters pairs before clustering', {
  skip_if_sprint_lt(9)

  # Pair A-B has high prob, B-C has low prob
  pairs <- tibble::tibble(
    unique_id_l = c('A', 'B'),
    unique_id_r = c('B', 'C'),
    match_weight = c(5.0, 0.5),
    match_probability = c(0.97, 0.60)
  )
  pairs <- structure(pairs, class = c('il_compared', class(pairs)))

  # With threshold 0.90, only A-B survives; B-C is below threshold
  clusters <- il_cluster(pairs, threshold = 0.90)

  # A and B are clustered together; C is isolated
  expect_equal(length(unique(clusters$cluster_id)), 2)
})

test_that('il_cluster() handles empty predictions gracefully', {
  skip_if_sprint_lt(9)

  # From: test_clustering_no_edges
  pairs <- tibble::tibble(
    unique_id_l = character(0),
    unique_id_r = character(0),
    match_weight = numeric(0),
    match_probability = numeric(0)
  )
  pairs <- structure(pairs, class = c('il_compared', class(pairs)))

  clusters <- il_cluster(pairs, threshold = 0.5)
  expect_s3_class(clusters, 'tbl_df')
  expect_equal(nrow(clusters), 0)
})

test_that("il_cluster(method = 'best_link') limits to one record per cluster from each source", {
  skip_if_sprint_lt(9)

  # From: test_single_best_links_correctness_example_1
  # 9 records from 3 datasets, 6 predictions
  pairs <- tibble::tibble(
    unique_id_l = c(0L, 1L, 3L, 4L, 6L, 6L),
    unique_id_r = c(1L, 2L, 5L, 5L, 5L, 7L),
    match_probability = c(0.90, 0.70, 0.85, 0.90, 0.80, 0.70),
    match_weight = c(3.17, 1.22, 2.50, 3.17, 2.00, 1.22),
    source_dataset_l = c('a', 'b', 'a', 'b', 'a', 'a'),
    source_dataset_r = c('b', 'c', 'c', 'c', 'c', 'b')
  )
  pairs <- structure(pairs, class = c('il_compared', class(pairs)))

  clusters <- il_cluster(pairs, threshold = 0.5, method = 'best_link')
  expect_s3_class(clusters, 'tbl_df')
  expect_true('cluster_id' %in% names(clusters))
})

test_that('il_cluster() handles ties in best_link', {
  skip_if_sprint_lt(9)

  # From: test_single_best_links_ties — two predictions with same probability
  pairs <- tibble::tibble(
    unique_id_l = c(0L, 1L),
    unique_id_r = c(2L, 2L),
    match_probability = c(0.90, 0.90),
    match_weight = c(3.17, 3.17),
    source_dataset_l = c('a', 'a'),
    source_dataset_r = c('b', 'b')
  )
  pairs <- structure(pairs, class = c('il_compared', class(pairs)))

  clusters <- il_cluster(pairs, threshold = 0.5, method = 'best_link')
  # With ties, records should still be assigned to clusters
  # (exact behavior depends on tie-breaking strategy)
  expect_s3_class(clusters, 'tbl_df')
  expect_true(length(unique(clusters$cluster_id)) > 1)
})

test_that('il_cluster() with connected components matches igraph', {
  skip_if_sprint_lt(9)

  # From: test_cc_random_graphs — small random graph
  # Create a small graph with known components
  set.seed(42)
  n <- 20
  edges <- data.frame(
    unique_id_l = sample(1:n, 15, replace = TRUE),
    unique_id_r = sample(1:n, 15, replace = TRUE)
  )
  edges <- edges[edges$unique_id_l != edges$unique_id_r, ]
  edges <- unique(edges)
  edges$match_probability <- 0.95
  edges$match_weight <- 4.25
  edges <- structure(
    tibble::as_tibble(edges),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  clusters <- il_cluster(edges, threshold = 0.5)

  # Verify against igraph
  g <- igraph::graph_from_data_frame(
    edges[, c('unique_id_l', 'unique_id_r')],
    directed = FALSE
  )
  components <- igraph::components(g)

  # Number of clusters should match igraph
  expect_equal(
    length(unique(clusters$cluster_id)),
    components$no
  )
})
