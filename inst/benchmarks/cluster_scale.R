devtools::load_all()
set.seed(42)

test_cluster <- function(n_edges, n_nodes, method = "connected") {
  ids_l <- as.character(sample(seq_len(n_nodes), n_edges, replace = TRUE))
  ids_r <- as.character(sample(seq_len(n_nodes), n_edges, replace = TRUE))
  probs <- runif(n_edges, 0.5, 1)
  pairs <- tibble::tibble(
    unique_id_l = ids_l, unique_id_r = ids_r,
    match_weight = rnorm(n_edges), match_probability = probs
  )
  pairs <- structure(pairs, class = c("il_compared", class(pairs)), model = NULL)
  t <- system.time(cl <- il_cluster(pairs, method = method))["elapsed"]
  cat(sprintf("  %7d edges, %6d nodes, %-10s: %6.3f s  (%d clusters)\n",
              n_edges, n_nodes, method, t, length(unique(cl$cluster_id))))
  flush.console()
}

cat("=== Clustering scaling (connected components) ===\n")
test_cluster(1000, 500)
test_cluster(5000, 2000)
test_cluster(10000, 5000)
test_cluster(20000, 5000)
test_cluster(50000, 10000)
test_cluster(100000, 20000)

cat("\n=== Clustering scaling (best_link) ===\n")
test_cluster(1000, 500, "best_link")
test_cluster(5000, 2000, "best_link")
test_cluster(10000, 5000, "best_link")
test_cluster(20000, 5000, "best_link")
test_cluster(50000, 10000, "best_link")

cat("\nDone.\n")
