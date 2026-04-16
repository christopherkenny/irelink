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
solve_cc_sql <- function(con, edges_tbl, max_iterations = 100L,
                         collect = TRUE) {
  # Check for empty edge set
  n_edges <- DBI::dbGetQuery(
    con, glue::glue('SELECT COUNT(*) AS n FROM {edges_tbl}')
  )$n
  if (n_edges == 0L) {
    output_tbl <- cc_tbl('output')
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {output_tbl}'))
    DBI::dbExecute(con, glue::glue(
      'CREATE TABLE {output_tbl} AS ',
      'SELECT CAST(NULL AS VARCHAR) AS node_id, CAST(NULL AS VARCHAR) AS cluster_id WHERE 1 = 0'
    ))
    if (!collect) {
      return(output_tbl)
    }
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

  # Clean up all intermediate tables (keep output for graph metrics)
  for (tbl in stable_tables) {
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  }
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {repr_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'DROP TABLE IF EXISTS {cc_tbl("neighbours")}'
  ))

  if (!collect) {
    return(output_tbl)
  }

  result <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {output_tbl}'))
  tibble::as_tibble(result)
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

# --- Iterative one-to-one clustering ----------------------------------------

#' Iterative one-to-one clustering (SQL)
#'
#' Implements splink's iterative best-link merge with dataset constraints.
#' Each iteration: (1) identify which datasets each cluster contains,
#' (2) rank candidate edges excluding those that would cause dataset
#' collisions, (3) keep mutual best pairs, (4) merge. Repeat until
#' no more merges are possible.
#'
#' @param con DBI connection.
#' @param edges_tbl Name of edges table (unique_id_l, unique_id_r,
#'   match_probability).
#' @param source_dataset Named character vector mapping unique_id →
#'   source_dataset.
#' @param ties_method How to break ties: `"lowest_id"` or `"drop"`.
#' @param max_iterations Safety valve (default 100).
#' @return A tibble with columns `node_id` and `cluster_id`.
#' @noRd
solve_one_to_one_sql <- function(con, edges_tbl, source_dataset,
                                 ties_method = 'lowest_id',
                                 max_iterations = 100L,
                                 collect = TRUE) {
  oto_repr <- cc_tbl('oto_repr')
  oto_src <- cc_tbl('oto_src')
  oto_cluster_ds <- cc_tbl('oto_cluster_ds')
  oto_ranked <- cc_tbl('oto_ranked')
  oto_merged <- cc_tbl('oto_merged')

  # Upload source dataset mapping
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {oto_src}'))
  sd_df <- data.frame(
    node_id = names(source_dataset),
    source_dataset = unname(source_dataset),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, oto_src, sd_df)

  # Initialize: each node is its own representative
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {oto_repr}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {oto_repr} AS ',
    'SELECT DISTINCT node_id, node_id AS representative ',
    'FROM (',
    '  SELECT unique_id_l AS node_id FROM {edges_tbl} ',
    '  UNION ',
    '  SELECT unique_id_r AS node_id FROM {edges_tbl}',
    ') sub'
  ))

  for (iter in seq_len(max_iterations)) {
    # Step 1: Build cluster→datasets mapping
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {oto_cluster_ds}'))
    DBI::dbExecute(con, glue::glue(
      'CREATE TABLE {oto_cluster_ds} AS ',
      'SELECT DISTINCT r.representative, s.source_dataset ',
      'FROM {oto_repr} r ',
      'INNER JOIN {oto_src} s ON r.node_id = s.node_id'
    ))

    # Step 2: Find candidate edges that don't violate constraints,
    # rank by probability, and keep mutual best
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {oto_ranked}'))

    tie_order <- if (ties_method == 'lowest_id') {
      ', CASE WHEN repr < partner_repr THEN partner_repr ELSE repr END'
    } else {
      ''
    }

    DBI::dbExecute(con, glue::glue(
      'CREATE TABLE {oto_ranked} AS ',
      'WITH candidate_edges AS (',
      '  SELECT e.unique_id_l, e.unique_id_r, e.match_probability, ',
      '         rl.representative AS repr_l, rr.representative AS repr_r ',
      '  FROM {edges_tbl} e ',
      '  INNER JOIN {oto_repr} rl ON e.unique_id_l = rl.node_id ',
      '  INNER JOIN {oto_repr} rr ON e.unique_id_r = rr.node_id ',
      '  WHERE rl.representative <> rr.representative ',
      '  AND NOT EXISTS (',
      '    SELECT 1 FROM {oto_cluster_ds} cdl ',
      '    INNER JOIN {oto_cluster_ds} cdr ',
      '      ON cdl.source_dataset = cdr.source_dataset ',
      '    WHERE cdl.representative = rl.representative ',
      '    AND cdr.representative = rr.representative',
      '  )',
      '), ',
      'bidir AS (',
      '  SELECT repr_l AS repr, repr_r AS partner_repr, ',
      '         match_probability AS prob, unique_id_l, unique_id_r ',
      '  FROM candidate_edges ',
      '  UNION ALL ',
      '  SELECT repr_r AS repr, repr_l AS partner_repr, ',
      '         match_probability AS prob, unique_id_l, unique_id_r ',
      '  FROM candidate_edges',
      '), ',
      'ranked AS (',
      '  SELECT *, ROW_NUMBER() OVER (',
      '    PARTITION BY repr ORDER BY prob DESC{tie_order}',
      '  ) AS rn ',
      '  FROM bidir',
      ') ',
      'SELECT DISTINCT unique_id_l, unique_id_r, prob AS match_probability, ',
      '       repr, partner_repr ',
      'FROM ranked r1 ',
      'WHERE r1.rn = 1 ',
      'AND EXISTS (',
      '  SELECT 1 FROM ranked r2 ',
      '  WHERE r2.repr = r1.partner_repr ',
      '  AND r2.partner_repr = r1.repr ',
      '  AND r2.rn = 1',
      ')'
    ))

    # Check if any merges happened
    n_merges <- DBI::dbGetQuery(
      con, glue::glue('SELECT COUNT(*) AS n FROM {oto_ranked}')
    )$n

    if (n_merges == 0L) break

    # Step 3: Merge clusters — update representatives
    # For each mutual-best pair, the new representative is MIN(repr_l, repr_r)
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {oto_merged}'))
    DBI::dbExecute(con, glue::glue(
      'CREATE TABLE {oto_merged} AS ',
      'WITH merge_pairs AS (',
      '  SELECT repr, partner_repr, ',
      '         CASE WHEN repr < partner_repr THEN repr ',
      '              ELSE partner_repr END AS new_repr ',
      '  FROM {oto_ranked}',
      '), ',
      'repr_map AS (',
      '  SELECT repr AS old_repr, MIN(new_repr) AS new_repr ',
      '  FROM merge_pairs ',
      '  GROUP BY repr',
      ') ',
      'SELECT r.node_id, ',
      '  COALESCE(m.new_repr, r.representative) AS representative ',
      'FROM {oto_repr} r ',
      'LEFT JOIN repr_map m ON r.representative = m.old_repr'
    ))

    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {oto_repr}'))
    DBI::dbExecute(con, glue::glue(
      'ALTER TABLE {oto_merged} RENAME TO {oto_repr}'
    ))
  }

  output_tbl <- cc_tbl('output')
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {output_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {output_tbl} AS ',
    'SELECT node_id, representative AS cluster_id FROM {oto_repr}'
  ))

  # Clean up
  for (tbl in c(oto_repr, oto_src, oto_cluster_ds, oto_ranked, oto_merged)) {
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  }

  if (!collect) {
    return(output_tbl)
  }

  result <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {output_tbl}'))
  tibble::as_tibble(result)
}


#' Iterative one-to-one clustering (R/igraph fallback)
#'
#' R-side version of the iterative best-link algorithm with dataset
#' constraints. Used when no DuckDB/PostgreSQL connection is available.
#'
#' @param pairs An il_compared tibble (already threshold-filtered).
#' @param source_dataset Named character vector mapping unique_id →
#'   source_dataset.
#' @param ties_method How to break ties: `"lowest_id"` or `"drop"`.
#' @param max_iterations Safety valve (default 100).
#' @return A tibble with columns `unique_id` and `cluster_id`.
#' @noRd
solve_one_to_one_r <- function(pairs, source_dataset,
                               ties_method = 'lowest_id',
                               max_iterations = 100L) {
  all_ids <- unique(c(
    as.character(pairs$unique_id_l),
    as.character(pairs$unique_id_r)
  ))

  # Initialize: each node is its own representative
  repr <- stats::setNames(all_ids, all_ids)

  edges <- data.frame(
    id_l = as.character(pairs$unique_id_l),
    id_r = as.character(pairs$unique_id_r),
    prob = pairs$match_probability,
    stringsAsFactors = FALSE
  )

  for (iter in seq_len(max_iterations)) {
    # Get cluster (representative) for each endpoint
    repr_l <- repr[edges$id_l]
    repr_r <- repr[edges$id_r]

    # Only consider edges between different clusters
    cross <- repr_l != repr_r
    if (!any(cross)) break

    ce <- edges[cross, , drop = FALSE]
    cr_l <- repr_l[cross]
    cr_r <- repr_r[cross]

    # Build cluster→datasets mapping
    cluster_datasets <- split(
      source_dataset[all_ids[all_ids %in% names(source_dataset)]],
      repr[all_ids[all_ids %in% names(source_dataset)]]
    )
    cluster_datasets <- lapply(cluster_datasets, unique)

    # Filter: remove edges where merging would cause dataset collision
    valid <- vapply(seq_len(nrow(ce)), function(i) {
      ds_l <- cluster_datasets[[cr_l[i]]]
      ds_r <- cluster_datasets[[cr_r[i]]]
      if (is.null(ds_l) || is.null(ds_r)) {
        return(TRUE)
      }
      !any(ds_l %in% ds_r)
    }, logical(1))

    if (!any(valid)) break

    ce <- ce[valid, , drop = FALSE]
    cr_l <- cr_l[valid]
    cr_r <- cr_r[valid]

    # Bidirectional: find best partner for each cluster representative
    best_partner <- list()
    best_prob <- list()

    for (i in seq_len(nrow(ce))) {
      for (side in 1:2) {
        cl <- if (side == 1) cr_l[i] else cr_r[i]
        partner <- if (side == 1) cr_r[i] else cr_l[i]
        p <- ce$prob[i]
        prev_p <- best_prob[[cl]]

        if (is.null(prev_p)) {
          best_partner[[cl]] <- partner
          best_prob[[cl]] <- p
        } else if (p > prev_p) {
          best_partner[[cl]] <- partner
          best_prob[[cl]] <- p
        } else if (p == prev_p && ties_method == 'lowest_id') {
          if (partner < best_partner[[cl]]) {
            best_partner[[cl]] <- partner
          }
        }
      }
    }

    if (ties_method == 'drop') {
      # Drop clusters with tied best probability
      tie_count <- list()
      for (i in seq_len(nrow(ce))) {
        for (side in 1:2) {
          cl <- if (side == 1) cr_l[i] else cr_r[i]
          if (ce$prob[i] == best_prob[[cl]]) {
            tie_count[[cl]] <- (tie_count[[cl]] %||% 0L) + 1L
          }
        }
      }
      tied <- names(tie_count)[vapply(tie_count, function(x) x > 1L, logical(1))]
      for (cl in tied) {
        best_partner[[cl]] <- NULL
        best_prob[[cl]] <- NULL
      }
    }

    # Keep only mutual best pairs
    merged_any <- FALSE
    already_merged <- character(0)
    for (cl in names(best_partner)) {
      partner <- best_partner[[cl]]
      if (is.null(partner)) next
      if (cl %in% already_merged || partner %in% already_merged) next
      partner_best <- best_partner[[partner]]
      if (!is.null(partner_best) && partner_best == cl) {
        # Mutual best — merge: assign all nodes in larger-id cluster
        # to smaller-id cluster
        new_rep <- min(cl, partner)
        old_rep <- max(cl, partner)
        repr[repr == old_rep] <- new_rep
        already_merged <- c(already_merged, cl, partner)
        merged_any <- TRUE
      }
    }

    if (!merged_any) break
  }

  tibble::tibble(
    unique_id = all_ids,
    cluster_id = paste0('cluster_', unname(repr[all_ids]))
  )
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
