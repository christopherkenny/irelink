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
  pairs <- ensure_collected(pairs)
  # Try SQL path first
  model <- attr(pairs, 'model')
  con <- if (!is.null(model)) model$con else NULL
  use_sql <- !is.null(con) && DBI::dbIsValid(con) &&
    detect_dialect(con) %in% c('duckdb', 'postgres')

  if (use_sql) {
    return(graph_metrics_sql(con, pairs, clusters))
  }

  graph_metrics_r(pairs, clusters)
}

#' SQL-path graph metrics
#' @noRd
graph_metrics_sql <- function(con, pairs, clusters) {
  # Upload edges
  edges_tbl <- cc_tbl('metrics_edges')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {edges_tbl}'))
  edges_df <- data.frame(
    unique_id_l = as.character(pairs$unique_id_l),
    unique_id_r = as.character(pairs$unique_id_r),
    match_probability = pairs$match_probability,
    match_weight = pairs$match_weight,
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, edges_tbl, edges_df)

  # Upload cluster assignments
  cc_tbl_name <- cc_tbl('metrics_cc')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {cc_tbl_name}'))
  cc_df <- data.frame(
    node_id = as.character(clusters$unique_id),
    cluster_id = as.character(clusters$cluster_id),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, cc_tbl_name, cc_df)

  # Node metrics via SQL
  nm_tbl <- sql_node_metrics(con, cc_tbl_name, edges_tbl)
  nodes_raw <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {nm_tbl}'))
  nodes <- tibble::tibble(
    unique_id = nodes_raw$node_id,
    cluster_id = nodes_raw$cluster_id,
    degree = as.integer(nodes_raw$node_degree)
  )

  # Cluster metrics via SQL
  cm_tbl <- sql_cluster_metrics(con, nm_tbl)
  clusters_raw <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {cm_tbl}'))
  cluster_tbl <- tibble::tibble(
    cluster_id = clusters_raw$cluster_id,
    n_nodes = as.integer(clusters_raw$n_nodes),
    n_edges = as.integer(clusters_raw$n_edges),
    density = clusters_raw$density
  )

  # Edge-level (compute bridges via igraph, merge back)
  edges <- tibble::tibble(
    unique_id_l = as.character(pairs$unique_id_l),
    unique_id_r = as.character(pairs$unique_id_r),
    match_probability = pairs$match_probability,
    match_weight = pairs$match_weight,
    is_bridge = compute_bridges(
      as.character(pairs$unique_id_l),
      as.character(pairs$unique_id_r)
    )
  )

  # Clean up
  for (tbl in c(edges_tbl, cc_tbl_name, nm_tbl, cm_tbl)) {
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  }

  list(nodes = nodes, edges = edges, clusters = cluster_tbl)
}

#' R-path graph metrics (fallback)
#' @noRd
graph_metrics_r <- function(pairs, clusters) {
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
    match_weight = pairs$match_weight,
    is_bridge = compute_bridges(edge_ids_l, edge_ids_r)
  )
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

#' Compute bridge flags for edges
#'
#' Uses igraph to identify bridge edges — edges whose removal would
#' disconnect the graph.
#'
#' @param id_l,id_r Character vectors of edge endpoints.
#' @return Logical vector of the same length, TRUE for bridge edges.
#' @noRd
compute_bridges <- function(id_l, id_r) {
  n <- length(id_l)
  if (n == 0L) return(logical(0))

  if (!requireNamespace('igraph', quietly = TRUE)) {
    cli::cli_warn(
      'Package {.pkg igraph} is needed for bridge detection. Returning {.val FALSE} for all edges.'
    )
    return(rep(FALSE, n))
  }

  el <- data.frame(from = id_l, to = id_r, stringsAsFactors = FALSE)
  g <- igraph::graph_from_data_frame(el, directed = FALSE)
  bridge_ids <- igraph::bridges(g)

  is_bridge <- rep(FALSE, n)
  is_bridge[bridge_ids] <- TRUE
  is_bridge
}