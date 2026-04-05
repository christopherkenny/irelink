# SQL-based connected components and graph metrics.
# Implements splink's iterative representative-propagation algorithm
# entirely in SQL (no graph library needed for the primary path).
# Reference: https://arxiv.org/pdf/1802.09478.pdf
#
# The R-side driver loop is thin: fire SQL, check convergence, repeat.
# Typical convergence: 3-7 iterations even for large graphs.

# Table names used by the CC algorithm
cc_tbl <- function(name) paste0('__il_cc_', name)

#' Upload an edge list to the database for clustering
#'
#' Creates a minimal `__il_cc_edges` table with just the two ID columns
#' and optional match_probability for threshold filtering.
#'
#' @param con DBI connection.
#' @param pairs An il_compared tibble (or data frame with unique_id_l/r).
#' @param threshold Optional. If non-NULL, only edges at or above this
#'   match probability are uploaded.
#' @return The table name (character).
#' @noRd
cc_upload_edges <- function(con, pairs, threshold = NULL) {
  if (!is.null(threshold)) {
    pairs <- pairs[which(pairs$match_probability >= threshold), , drop = FALSE]
  }
  edges <- data.frame(
    unique_id_l = as.character(pairs$unique_id_l),
    unique_id_r = as.character(pairs$unique_id_r),
    stringsAsFactors = FALSE
  )
  if ('match_probability' %in% names(pairs)) {
    edges$match_probability <- pairs$match_probability
  }
  tbl <- cc_tbl('edges')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  DBI::dbWriteTable(con, tbl, edges)
  tbl
}

#' Initialise the CC algorithm tables
#'
#' Creates:
#' - `__il_cc_neighbours`: bidirectional edges (each edge in both directions)
#' - `__il_cc_representatives`: initial representative = self for every node
#'
#' @param con DBI connection.
#' @param edges_tbl Name of the edges table.
#' @return Invisibly, the representative table name.
#' @noRd
cc_initialise <- function(con, edges_tbl) {
  neighbours_tbl <- cc_tbl('neighbours')
  repr_tbl <- cc_tbl('representatives')

  # Bidirectional edge list
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {neighbours_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {neighbours_tbl} AS ',
    'SELECT unique_id_l AS node_id, unique_id_l AS node_rep, ',
    '       unique_id_r AS neighbour, unique_id_r AS neighbour_rep ',
    'FROM {edges_tbl} ',
    'UNION ALL ',
    'SELECT unique_id_r AS node_id, unique_id_r AS node_rep, ',
    '       unique_id_l AS neighbour, unique_id_l AS neighbour_rep ',
    'FROM {edges_tbl}'
  ))

  # Initial representatives: every node is its own representative
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {repr_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {repr_tbl} AS ',
    'SELECT DISTINCT node_id, node_id AS representative ',
    'FROM (',
    '  SELECT unique_id_l AS node_id FROM {edges_tbl} ',
    '  UNION ',
    '  SELECT unique_id_r AS node_id FROM {edges_tbl}',
    ') nodes'
  ))

  invisible(repr_tbl)
}

#' Run one iteration of representative propagation
#'
#' For each current representative, compute the minimum representative
#' across all its neighbours. Then update the node→representative mapping.
#' Split into stable (no outgoing cross-cluster edges) and unstable.
#'
#' @param con DBI connection.
#' @param iteration Integer iteration number (for table naming).
#' @return A list with `stable_tbl` and `unstable_tbl` names, and
#'   `n_remaining` (number of cross-cluster edges remaining).
#' @noRd
cc_iterate <- function(con, iteration) {
  neighbours_tbl <- cc_tbl('neighbours')
  repr_tbl <- cc_tbl('representatives')
  updates_tbl <- cc_tbl('rep_updates')
  new_repr_tbl <- cc_tbl(paste0('repr_', iteration))
  stable_tbl <- cc_tbl(paste0('stable_', iteration))
  unstable_tbl <- cc_tbl(paste0('unstable_', iteration))
  new_neighbours_tbl <- cc_tbl(paste0('neighbours_', iteration))

  # Step 1: Compute new representatives (min across neighbours + self)
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {updates_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {updates_tbl} AS ',
    'SELECT old_rep, MIN(representative) AS representative, ',
    '       MIN(stable) AS stable ',
    'FROM (',
    '  SELECT node_rep AS old_rep, neighbour_rep AS representative, ',
    '         0 AS stable ',
    '  FROM {neighbours_tbl} ',
    '  UNION ALL ',
    '  SELECT representative AS old_rep, representative, 1 AS stable ',
    '  FROM {repr_tbl}',
    ') sub ',
    'GROUP BY old_rep'
  ))

  # Step 2: Map updates back to node_ids
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {new_repr_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {new_repr_tbl} AS ',
    'SELECT prev.node_id, upd.representative, upd.stable ',
    'FROM {updates_tbl} upd ',
    'INNER JOIN {repr_tbl} prev ',
    '  ON upd.old_rep = prev.representative'
  ))

  # Step 3: Split stable / unstable
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {stable_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {stable_tbl} AS ',
    'SELECT node_id, representative FROM {new_repr_tbl} WHERE stable = 1'
  ))

  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {unstable_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {unstable_tbl} AS ',
    'SELECT node_id, representative FROM {new_repr_tbl} WHERE stable = 0'
  ))

  # Step 4: Filter neighbours to only cross-cluster edges
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {new_neighbours_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {new_neighbours_tbl} AS ',
    'SELECT l.representative AS node_rep, n.node_id, ',
    '       n.neighbour, r.representative AS neighbour_rep ',
    'FROM {neighbours_tbl} n ',
    'INNER JOIN {new_repr_tbl} l ON l.node_id = n.node_id ',
    'INNER JOIN {new_repr_tbl} r ON r.node_id = n.neighbour ',
    'WHERE l.representative <> r.representative'
  ))

  # Count remaining cross-cluster edges
  n_remaining <- DBI::dbGetQuery(
    con,
    glue::glue('SELECT COUNT(*) AS n FROM {new_neighbours_tbl}')
  )$n

  # Rotate: new tables become current for next iteration
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {updates_tbl}'))
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {neighbours_tbl}'))
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {repr_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'ALTER TABLE {new_neighbours_tbl} RENAME TO {neighbours_tbl}'
  ))
  DBI::dbExecute(con, glue::glue(
    'ALTER TABLE {unstable_tbl} RENAME TO {repr_tbl}'
  ))

  # Clean up iteration-specific tables (keep stable)
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {new_repr_tbl}'))

  list(stable_tbl = stable_tbl, n_remaining = n_remaining)
}

#' Run the full SQL connected-components algorithm
#'
#' Iterates representative propagation until convergence, then merges
#' all stable cluster tables into a single output.
#'
#' @param con DBI connection.
#' @param edges_tbl Name of the edges table (unique_id_l, unique_id_r).
#' @param max_iterations Safety valve (default 100).
#' @return A tibble with columns `node_id` and `cluster_id`.
#' @noRd
solve_cc_sql <- function(con, edges_tbl, max_iterations = 100L) {
  # Check for empty edge set
  n_edges <- DBI::dbGetQuery(
    con, glue::glue('SELECT COUNT(*) AS n FROM {edges_tbl}')
  )$n
  if (n_edges == 0L) {
    # All nodes are isolated — get distinct nodes from edges (empty)
    return(tibble::tibble(
      node_id = character(0), cluster_id = character(0)
    ))
  }

  cc_initialise(con, edges_tbl)

  stable_tables <- character(0)
  for (i in seq_len(max_iterations)) {
    result <- cc_iterate(con, i)
    stable_tables <- c(stable_tables, result$stable_tbl)

    if (result$n_remaining == 0L) break
  }

  # Include any remaining unstable nodes (final iteration's representatives)
  repr_tbl <- cc_tbl('representatives')

  # Merge all stable tables + remaining unstable
  all_tables <- c(stable_tables, repr_tbl)
  union_parts <- vapply(all_tables, function(tbl) {
    glue::glue('SELECT node_id, representative AS cluster_id FROM {tbl}')
  }, character(1))
  union_sql <- paste(union_parts, collapse = ' UNION ALL ')

  output_tbl <- cc_tbl('output')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {output_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {output_tbl} AS {union_sql}'
  ))

  # Read result
  result <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {output_tbl}'))

  # Clean up all intermediate tables (keep output for graph metrics)
  for (tbl in stable_tables) {
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  }
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {repr_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'DROP TABLE IF EXISTS {cc_tbl("neighbours")}'
  ))

  tibble::as_tibble(result)
}

#' Clean up all CC intermediate tables from the database
#' @param con DBI connection.
#' @noRd
cc_cleanup <- function(con) {
  tables <- DBI::dbListTables(con)
  cc_tables <- tables[grepl('^__il_cc_', tables)]
  for (tbl in cc_tables) {
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  }
}

# --- SQL best-link filter ---------------------------------------------------

#' Filter to mutual best links using SQL window functions
#'
#' For each node, keeps only the edge with the highest match_probability.
#' An edge survives only if it is the best link for BOTH endpoints.
#'
#' @param con DBI connection.
#' @param edges_tbl Name of edges table (must have unique_id_l,
#'   unique_id_r, match_probability).
#' @return Name of the filtered edges table.
#' @noRd
sql_best_link_filter <- function(con, edges_tbl, ties_method = 'lowest_id') {
  filtered_tbl <- cc_tbl('best_link')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {filtered_tbl}'))

  if (ties_method == 'drop') {
    # Identify nodes with more than one edge tied at their maximum probability,
    # then exclude all edges touching those tied nodes.
    DBI::dbExecute(con, glue::glue(
      'CREATE TABLE {filtered_tbl} AS ',
      'WITH bidir AS (',
      '  SELECT unique_id_l AS node, unique_id_r AS partner, match_probability AS prob ',
      '  FROM {edges_tbl} ',
      '  UNION ALL ',
      '  SELECT unique_id_r AS node, unique_id_l AS partner, match_probability AS prob ',
      '  FROM {edges_tbl}',
      '), ',
      'max_prob AS (',
      '  SELECT node, MAX(prob) AS best_prob FROM bidir GROUP BY node',
      '), ',
      'best_edges AS (',
      '  SELECT b.node, b.partner ',
      '  FROM bidir b JOIN max_prob m ON b.node = m.node AND b.prob = m.best_prob',
      '), ',
      'unique_best AS (',
      '  SELECT node, partner FROM best_edges GROUP BY node HAVING COUNT(*) = 1',
      ') ',
      'SELECT e.unique_id_l, e.unique_id_r, e.match_probability ',
      'FROM {edges_tbl} e ',
      'WHERE EXISTS (',
      '  SELECT 1 FROM unique_best u1 ',
      '  WHERE u1.node = e.unique_id_l AND u1.partner = e.unique_id_r',
      ') ',
      'AND EXISTS (',
      '  SELECT 1 FROM unique_best u2 ',
      '  WHERE u2.node = e.unique_id_r AND u2.partner = e.unique_id_l',
      ')'
    ))
  } else {
    # 'lowest_id': break ties by keeping the edge to the smaller partner id.
    DBI::dbExecute(con, glue::glue(
      'CREATE TABLE {filtered_tbl} AS ',
      'WITH bidir AS (',
      '  SELECT unique_id_l AS node, unique_id_r AS partner, ',
      '         match_probability AS prob ',
      '  FROM {edges_tbl} ',
      '  UNION ALL ',
      '  SELECT unique_id_r AS node, unique_id_l AS partner, ',
      '         match_probability AS prob ',
      '  FROM {edges_tbl}',
      '), ',
      'ranked AS (',
      '  SELECT *, ROW_NUMBER() OVER (',
      '    PARTITION BY node ORDER BY prob DESC, partner',
      '  ) AS rn ',
      '  FROM bidir',
      '), ',
      'best AS (',
      '  SELECT node, partner FROM ranked WHERE rn = 1',
      ') ',
      'SELECT e.unique_id_l, e.unique_id_r, e.match_probability ',
      'FROM {edges_tbl} e ',
      'WHERE EXISTS (',
      '  SELECT 1 FROM best b1 ',
      '  WHERE b1.node = e.unique_id_l AND b1.partner = e.unique_id_r',
      ') ',
      'AND EXISTS (',
      '  SELECT 1 FROM best b2 ',
      '  WHERE b2.node = e.unique_id_r AND b2.partner = e.unique_id_l',
      ')'
    ))
  }

  filtered_tbl
}

# --- SQL graph metrics ------------------------------------------------------

#' Compute node-level graph metrics in SQL
#'
#' Calculates node degree and cluster size using a LEFT JOIN on
#' bidirectional edges plus a window function.
#'
#' @param con DBI connection.
#' @param cc_output_tbl Name of the CC output table (node_id, cluster_id).
#' @param edges_tbl Name of the original edges table.
#' @return Name of the node metrics table.
#' @noRd
sql_node_metrics <- function(con, cc_output_tbl, edges_tbl) {
  bidir_tbl <- cc_tbl('bidir_edges')
  node_metrics_tbl <- cc_tbl('node_metrics')

  # Build bidirectional edges for degree computation
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {bidir_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {bidir_tbl} AS ',
    'SELECT unique_id_l AS node, unique_id_r AS neighbour FROM {edges_tbl} ',
    'UNION ALL ',
    'SELECT unique_id_r AS node, unique_id_l AS neighbour FROM {edges_tbl}'
  ))

  # Node degree + cluster size
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {node_metrics_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {node_metrics_tbl} AS ',
    'SELECT c.node_id, c.cluster_id, ',
    '  CAST(COUNT(n.neighbour) AS INTEGER) AS node_degree, ',
    '  CAST(COUNT(*) OVER (PARTITION BY c.cluster_id) AS INTEGER) AS cluster_size ',
    'FROM {cc_output_tbl} c ',
    'LEFT JOIN {bidir_tbl} n ON c.node_id = n.node ',
    'GROUP BY c.node_id, c.cluster_id'
  ))

  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {bidir_tbl}'))
  node_metrics_tbl
}

#' Compute cluster-level graph metrics in SQL
#'
#' Calculates n_nodes, n_edges, density, and centralisation from the
#' node metrics table in a single GROUP BY pass.
#'
#' @param con DBI connection.
#' @param node_metrics_tbl Name of the node metrics table.
#' @return Name of the cluster metrics table.
#' @noRd
sql_cluster_metrics <- function(con, node_metrics_tbl) {
  cluster_tbl <- cc_tbl('cluster_metrics')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {cluster_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {cluster_tbl} AS ',
    'SELECT cluster_id, ',
    '  CAST(COUNT(*) AS INTEGER) AS n_nodes, ',
    '  CAST(SUM(node_degree) / 2 AS INTEGER) AS n_edges, ',
    '  CASE WHEN COUNT(*) > 1 ',
    '    THEN (2.0 * SUM(node_degree) / 2.0) / ',
    '         (CAST(COUNT(*) AS DOUBLE) * (COUNT(*) - 1)) ',
    '    ELSE 0.0 END AS density, ',
    '  CASE WHEN COUNT(*) > 2 ',
    '    THEN (1.0 * COUNT(*) * MAX(node_degree) - SUM(node_degree)) / ',
    '         ((COUNT(*) - 1.0) * (COUNT(*) - 2.0)) ',
    '    ELSE NULL END AS cluster_centralisation ',
    'FROM {node_metrics_tbl} ',
    'GROUP BY cluster_id'
  ))
  cluster_tbl
}
