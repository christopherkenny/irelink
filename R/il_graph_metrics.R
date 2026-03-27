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
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c(
#'     'John', 'Jon', 'Jane', 'Jane', 'Bob',
#'     'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
#'     'John', 'Jon', 'Jane', 'Janet', 'Bob',
#'     'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
#'   ),
#'   surname = c(
#'     'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Brown', 'White', 'White',
#'     'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Browne', 'White', 'White'
#'   ),
#'   dob = c(
#'     '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
#'     '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
#'     '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
#'     '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
#'     '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
#'   ),
#'   city = c(
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
#'   ),
#'   email = c(
#'     'john@example.com', 'jon@example.com', 'jane@example.com',
#'     'jane@example.com', 'bob@example.com', 'bobby@example.com',
#'     'alice@example.com', 'alicia@example.com', 'tom@example.com',
#'     'thomas@example.com', 'john@example.com', 'jon@example.com',
#'     'jane@example.com', 'janet@example.com', 'bob@example.com',
#'     'robert@example.com', 'alice@example.com', 'alison@example.com',
#'     'tom@example.com', 'tomas@example.com'
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' pairs <- predict(model, threshold = 0.5)
#' clusters <- il_cluster(pairs)
#'
#' metrics <- il_graph_metrics(pairs, clusters)
#' metrics$clusters
#' DBI::dbDisconnect(con, shutdown = TRUE)
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
