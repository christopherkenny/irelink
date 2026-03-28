devtools::load_all()
set.seed(42)

bench_cluster <- function(n_edges, n_nodes, method = "connected") {
  ids_l <- as.character(sample(seq_len(n_nodes), n_edges, replace = TRUE))
  ids_r <- as.character(sample(seq_len(n_nodes), n_edges, replace = TRUE))
  pairs <- tibble::tibble(
    unique_id_l = ids_l, unique_id_r = ids_r,
    match_weight = rnorm(n_edges), match_probability = runif(n_edges, 0.5, 1)
  )
  pairs <- structure(pairs, class = c("il_compared", class(pairs)), model = NULL)
  t <- system.time(cl <- il_cluster(pairs, method = method))["elapsed"]
  tibble::tibble(
    n_edges = n_edges, n_nodes = n_nodes, method = method,
    elapsed = t, n_clusters = length(unique(cl$cluster_id))
  )
}

configs <- list(c(1000, 500), c(5000, 2000), c(10000, 5000),
                c(20000, 5000), c(50000, 10000), c(100000, 20000))

# Connected components
lapply(configs, \(x) bench_cluster(x[1], x[2])) |> dplyr::bind_rows()

# Best link (skip largest config)
lapply(configs[-6], \(x) bench_cluster(x[1], x[2], "best_link")) |> dplyr::bind_rows()
