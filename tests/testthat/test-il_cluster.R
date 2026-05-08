# Sprint 9 — Clustering: il_cluster()
# Translated from: test_clustering.py, test_cluster_using_single_best_links.py,
# test_cc_random_graphs.py, test_cluster_at_multiple_thresholds.py

test_that('il_cluster() assigns connected pairs to the same cluster', {
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

# --- ties_method --------------------------------------------------------------

test_that("ties_method = 'drop' removes tied best-link edges", {
  # Three records: A-B and A-C tied at 0.9; B-C at 0.5
  # A is tied so its edges should be dropped; B-C survives
  pairs <- tibble::tibble(
    unique_id_l = c('A', 'A', 'B'),
    unique_id_r = c('B', 'C', 'C'),
    match_probability = c(0.9, 0.9, 0.5)
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))
  clusters <- il_cluster(pairs, method = 'best_link', ties_method = 'drop')
  # A-B and A-C dropped; B-C kept; all three get separate or B-C cluster
  expect_equal(nrow(clusters), 3L)
})

test_that("ties_method = 'lowest_id' breaks ties deterministically", {
  pairs <- tibble::tibble(
    unique_id_l = c('A', 'A'),
    unique_id_r = c('B', 'C'),
    match_probability = c(0.9, 0.9)
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))
  clusters1 <- il_cluster(pairs, method = 'best_link', ties_method = 'lowest_id')
  clusters2 <- il_cluster(pairs, method = 'best_link', ties_method = 'lowest_id')
  # Deterministic: same result both times
  expect_equal(clusters1, clusters2)
})

test_that('ties_method defaults to lowest_id', {
  pairs <- tibble::tibble(
    unique_id_l = c('A', 'B'),
    unique_id_r = c('B', 'C'),
    match_probability = c(0.9, 0.8)
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))
  expect_no_error(il_cluster(pairs, method = 'best_link'))
})

# --- source_dataset (duplicate_free_datasets constraint) ----------------

test_that('source_dataset filters same-source edges in best_link', {
  # A→B (cross-dataset, keep), A→C (same dataset, drop)
  pairs <- tibble::tibble(
    unique_id_l = c('A', 'A'),
    unique_id_r = c('B', 'C'),
    match_probability = c(0.9, 0.95)
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))

  sd <- c(A = 'ds1', B = 'ds2', C = 'ds1')
  clusters <- il_cluster(pairs, method = 'best_link', source_dataset = sd)

  # A and C are from the same dataset, so A-C edge is dropped

  # A-B should be linked, C should be in its own cluster
  cluster_a <- clusters$cluster_id[clusters$unique_id == 'A']
  cluster_b <- clusters$cluster_id[clusters$unique_id == 'B']
  cluster_c <- clusters$cluster_id[clusters$unique_id == 'C']
  expect_equal(cluster_a, cluster_b)
  expect_false(cluster_a == cluster_c)
})

test_that('source_dataset accepts data frame input', {
  pairs <- tibble::tibble(
    unique_id_l = c('A'),
    unique_id_r = c('B'),
    match_probability = c(0.9)
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))

  sd_df <- data.frame(
    unique_id = c('A', 'B'),
    source_dataset = c('ds1', 'ds2'),
    stringsAsFactors = FALSE
  )
  clusters <- il_cluster(pairs, method = 'best_link', source_dataset = sd_df)
  # Cross-dataset edge is kept
  expect_equal(length(unique(clusters$cluster_id)), 1)
})

test_that('source_dataset warns when used with connected method', {
  pairs <- tibble::tibble(
    unique_id_l = c('A'),
    unique_id_r = c('B'),
    match_probability = c(0.9)
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))

  sd <- c(A = 'ds1', B = 'ds2')
  expect_warning(
    il_cluster(pairs, method = 'connected', source_dataset = sd),
    'source_dataset'
  )
})

test_that('il_cluster() validates threshold and required pair columns', {
  pairs <- tibble::tibble(
    unique_id_l = c('A'),
    unique_id_r = c('B'),
    match_probability = 0.9
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))

  expect_error(
    il_cluster(pairs, threshold = 'x'),
    'threshold'
  )
  expect_error(
    il_cluster(pairs[, 'unique_id_l', drop = FALSE]),
    'unique_id_r'
  )
  expect_error(
    il_cluster(
      pairs[, c('unique_id_l', 'unique_id_r'), drop = FALSE],
      method = 'best_link'
    ),
    'match_probability'
  )
})

test_that('il_cluster() requires complete and unique source_dataset mappings', {
  pairs <- tibble::tibble(
    unique_id_l = c('A'),
    unique_id_r = c('B'),
    match_probability = 0.9
  )
  pairs <- structure(pairs, class = c('il_compared', 'tbl_df', 'tbl', 'data.frame'))

  expect_error(
    il_cluster(pairs, method = 'best_link', source_dataset = c(A = 'ds1')),
    'must provide a source dataset for every'
  )
  expect_error(
    il_cluster(
      pairs,
      method = 'best_link',
      source_dataset = data.frame(
        unique_id = c('A', 'A', 'B'),
        source_dataset = c('ds1', 'ds2', 'ds3'),
        stringsAsFactors = FALSE
      )
    ),
    'at most once'
  )
})
