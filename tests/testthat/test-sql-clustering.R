# Sprint 10 — SQL Clustering: test that SQL CC matches igraph results

# Helper: make a fake il_compared tibble with a model attribute pointing to a con
make_sql_pairs <- function(con, id_l, id_r, prob = NULL) {
  if (is.null(prob)) prob <- rep(0.95, length(id_l))
  pairs <- tibble::tibble(
    unique_id_l = as.character(id_l),
    unique_id_r = as.character(id_r),
    match_weight = rep(4.0, length(id_l)),
    match_probability = prob
  )
  model <- list(con = con)
  attr(pairs, 'model') <- model
  structure(pairs, class = c('il_compared', class(pairs)))
}

test_that('SQL CC: simple connected components', {
  con <- test_con()
  on.exit(test_discon(con))

  # Two clusters: {A,B,C} and {D,E}
  pairs <- make_sql_pairs(con,
    id_l = c('A', 'B', 'D'),
    id_r = c('B', 'C', 'E')
  )

  clusters <- il_cluster(pairs)

  expect_equal(nrow(clusters), 5)
  expect_equal(length(unique(clusters$cluster_id)), 2)

  # A, B, C should share a cluster
  c_a <- clusters$cluster_id[clusters$unique_id == 'A']
  c_b <- clusters$cluster_id[clusters$unique_id == 'B']
  c_c <- clusters$cluster_id[clusters$unique_id == 'C']
  c_d <- clusters$cluster_id[clusters$unique_id == 'D']
  expect_equal(c_a, c_b)
  expect_equal(c_b, c_c)

  # D, E should share a different cluster
  c_e <- clusters$cluster_id[clusters$unique_id == 'E']
  expect_equal(c_d, c_e)
  expect_false(c_a == c_d)
})

test_that('SQL CC: threshold filtering works', {
  con <- test_con()
  on.exit(test_discon(con))

  # A-B has high prob, B-C has low prob
  pairs <- make_sql_pairs(con,
    id_l = c('A', 'B'),
    id_r = c('B', 'C'),
    prob = c(0.95, 0.40)
  )

  clusters <- il_cluster(pairs, threshold = 0.80)
  # Only A-B survives; C is isolated
  expect_equal(length(unique(clusters$cluster_id)), 2)
})

test_that('SQL CC: best_link method filters correctly', {
  con <- test_con()
  on.exit(test_discon(con))

  # Triangle: A-B(0.9), A-C(0.5), B-C(0.8)
  # A's best = B; B's best = A; C's best = B
  # Only A-B is mutual best → clusters are {A,B} and {C}
  pairs <- make_sql_pairs(con,
    id_l = c('A', 'A', 'B'),
    id_r = c('B', 'C', 'C'),
    prob = c(0.9, 0.5, 0.8)
  )

  clusters <- il_cluster(pairs, method = 'best_link')
  c_a <- clusters$cluster_id[clusters$unique_id == 'A']
  c_b <- clusters$cluster_id[clusters$unique_id == 'B']
  c_c <- clusters$cluster_id[clusters$unique_id == 'C']
  expect_equal(c_a, c_b)
  expect_false(c_a == c_c)
})

test_that('SQL CC: matches igraph on chain graph', {
  con <- test_con()
  on.exit(test_discon(con))

  # Chain: 1-2-3-4-5 → single cluster of 5
  pairs <- make_sql_pairs(con,
    id_l = c('1', '2', '3', '4'),
    id_r = c('2', '3', '4', '5')
  )

  sql_clusters <- il_cluster(pairs)

  # All 5 nodes in same cluster
  expect_equal(length(unique(sql_clusters$cluster_id)), 1)
  expect_equal(nrow(sql_clusters), 5)
})

test_that('SQL CC: handles star graph', {
  con <- test_con()
  on.exit(test_discon(con))

  # Star: hub connected to 4 spokes
  pairs <- make_sql_pairs(con,
    id_l = c('hub', 'hub', 'hub', 'hub'),
    id_r = c('s1', 's2', 's3', 's4')
  )

  clusters <- il_cluster(pairs)
  expect_equal(length(unique(clusters$cluster_id)), 1)
  expect_equal(nrow(clusters), 5)
})

test_that('SQL CC: many disconnected components', {
  con <- test_con()
  on.exit(test_discon(con))

  # 10 disconnected pairs → 10 clusters of 2
  pairs <- make_sql_pairs(con,
    id_l = paste0('L', 1:10),
    id_r = paste0('R', 1:10)
  )

  clusters <- il_cluster(pairs)
  expect_equal(length(unique(clusters$cluster_id)), 10)
  expect_equal(nrow(clusters), 20)
})

test_that('SQL CC: single edge', {
  con <- test_con()
  on.exit(test_discon(con))

  pairs <- make_sql_pairs(con, id_l = 'X', id_r = 'Y')
  clusters <- il_cluster(pairs)
  expect_equal(nrow(clusters), 2)
  expect_equal(length(unique(clusters$cluster_id)), 1)
})

test_that('SQL graph metrics match R path', {
  con <- test_con()
  on.exit(test_discon(con))

  # Triangle cluster + pair cluster
  pairs <- make_sql_pairs(con,
    id_l = c('A', 'B', 'A', 'D'),
    id_r = c('B', 'C', 'C', 'E'),
    prob = c(0.9, 0.8, 0.7, 0.95)
  )

  clusters <- il_cluster(pairs)
  metrics <- il_graph_metrics(pairs, clusters)

  # Check nodes
  expect_true('degree' %in% names(metrics$nodes))
  # Node B in triangle has degree 2
  b_deg <- metrics$nodes$degree[metrics$nodes$unique_id == 'B']
  expect_equal(b_deg, 2L)

  # Check clusters
  triangle_cid <- clusters$cluster_id[clusters$unique_id == 'A']
  tri_cl <- metrics$clusters[metrics$clusters$cluster_id == triangle_cid, ]
  expect_equal(tri_cl$n_nodes, 3L)
  expect_equal(tri_cl$n_edges, 3L)
  expect_equal(tri_cl$density, 1.0) # complete graph
})

test_that('SQL CC: results agree with igraph fallback', {
  con <- test_con()
  on.exit(test_discon(con))

  # Build a more complex graph
  pairs_data <- tibble::tibble(
    unique_id_l = c('1', '2', '3', '5', '5', '8', '9'),
    unique_id_r = c('2', '3', '4', '6', '7', '9', '10'),
    match_weight = rep(4.0, 7),
    match_probability = rep(0.95, 7)
  )

  # SQL path
  sql_pairs <- structure(pairs_data, class = c('il_compared', class(pairs_data)))
  attr(sql_pairs, 'model') <- list(con = con)
  sql_cl <- il_cluster(sql_pairs)

  # igraph path (no model attribute)
  r_pairs <- structure(pairs_data, class = c('il_compared', class(pairs_data)))
  r_cl <- cluster_igraph(r_pairs, threshold = NULL, method = 'connected')

  # Both should have same number of clusters
  expect_equal(length(unique(sql_cl$cluster_id)), length(unique(r_cl$cluster_id)))

  # Build cluster sets for comparison (ignoring naming)
  sql_sets <- split(sql_cl$unique_id, sql_cl$cluster_id)
  r_sets <- split(r_cl$unique_id, r_cl$cluster_id)
  sql_sets <- sort(vapply(sql_sets, function(x) paste(sort(x), collapse = ','), character(1)))
  r_sets <- sort(vapply(r_sets, function(x) paste(sort(x), collapse = ','), character(1)))
  expect_equal(unname(sql_sets), unname(r_sets))
})

test_that('SQL CC: cleanup removes temp tables', {
  con <- test_con()
  on.exit(test_discon(con))

  pairs <- make_sql_pairs(con,
    id_l = c('A', 'B'),
    id_r = c('B', 'C')
  )

  clusters <- il_cluster(pairs)

  # After clustering, intermediate tables should not linger
  # (only __il_cc_output and __il_cc_edges may remain)
  cc_cleanup(con)
  tables <- DBI::dbListTables(con)
  cc_tables <- tables[grepl('^__il_cc_', tables)]
  expect_equal(length(cc_tables), 0)
})
