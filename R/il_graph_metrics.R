#' Compute Graph Metrics for Clusters
#'
#' Returns node-, edge-, and cluster-level metrics from the linkage
#' graph. Useful for diagnosing cluster quality and identifying bridge
#' edges or weakly connected components.
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param clusters A tibble from [il_cluster()] with cluster assignments.
#'
#' @return A named list of three tibbles:
#'   \describe{
#'     \item{`nodes`}{Record-level metrics (degree, centrality).}
#'     \item{`edges`}{Edge-level metrics (match probability, bridge flag).}
#'     \item{`clusters`}{Cluster-level metrics (size, density).}
#'   }
#' @export
#'
#' @examples
#' \dontrun{
#' pairs <- predict(model, threshold = 0.85)
#' clusters <- il_cluster(pairs)
#' metrics <- il_graph_metrics(pairs, clusters)
#' metrics$clusters
#' }
il_graph_metrics <- function(pairs, clusters) {
  all_ids <- clusters$unique_id

  # Compute node degree
  edge_ids_l <- as.character(pairs$unique_id_l)
  edge_ids_r <- as.character(pairs$unique_id_r)
  all_edge_ids <- c(edge_ids_l, edge_ids_r)
  degree_tbl <- table(factor(all_edge_ids, levels = as.character(all_ids)))

  nodes <- tibble::tibble(
    unique_id = as.character(all_ids),
    cluster_id = clusters$cluster_id,
    degree = as.integer(degree_tbl[as.character(all_ids)])
  )

  # Edge-level metrics
  edges <- tibble::tibble(
    unique_id_l = edge_ids_l,
    unique_id_r = edge_ids_r,
    match_probability = pairs$match_probability,
    match_weight = pairs$match_weight
  )

  # Cluster-level metrics
  cluster_ids <- unique(clusters$cluster_id)
  n_nodes_vec <- integer(length(cluster_ids))
  n_edges_vec <- integer(length(cluster_ids))
  density_vec <- numeric(length(cluster_ids))

  for (i in seq_along(cluster_ids)) {
    cid <- cluster_ids[i]
    members <- clusters$unique_id[clusters$cluster_id == cid]
    n <- length(members)
    n_nodes_vec[i] <- n

    member_set <- as.character(members)
    n_e <- sum(edge_ids_l %in% member_set & edge_ids_r %in% member_set)
    n_edges_vec[i] <- n_e

    max_edges <- if (n >= 2L) n * (n - 1L) / 2L else 0L
    density_vec[i] <- if (max_edges > 0L) n_e / max_edges else 0
  }

  cluster_tbl <- tibble::tibble(
    cluster_id = cluster_ids,
    n_nodes = n_nodes_vec,
    n_edges = n_edges_vec,
    density = density_vec
  )

  list(nodes = nodes, edges = edges, clusters = cluster_tbl)
}
