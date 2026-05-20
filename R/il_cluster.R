#' Cluster Scored Pairs into Entities
#'
#' Groups scored record pairs into entity clusters using graph-based
#' methods. The result assigns cluster IDs to records that represent the
#' same real-world entity.
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param threshold An optional secondary match-probability threshold.
#'   If `NULL` (the default), the threshold from prediction is used.
#' @param method One of `"connected"` (default) for connected-components
#'   clustering, or `"best_link"` for single-best-link clustering.
#' @param ties_method How to handle tied best-link probabilities when
#'   `method = "best_link"`. `"lowest_id"` (default) keeps the edge to
#'   the record with the smaller `unique_id`. `"drop"` removes all edges
#'   where the best-link probability is tied.
#'
#' @param source_dataset An optional named character vector or data frame
#'   mapping `unique_id` values to their source dataset name. Used with
#'   `method = "best_link"` to enforce at-most-one-record per source
#'   dataset per cluster.
#'   If supplied, it must cover every `unique_id` present in `pairs`.
#'   If a data frame, it must contain columns `unique_id` and
#'   `source_dataset`, and `unique_id` values must be unique.
#'
#' @return A tibble with one row per input record, including a
#'   `cluster_id` column.
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
#'
#' pairs <- predict(model, threshold = 0.5)
#' clusters <- il_cluster(pairs)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_cluster <- function(
  pairs,
  threshold = NULL,
  method = c('connected', 'best_link'),
  ties_method = c('lowest_id', 'drop'),
  source_dataset = NULL
) {
  method <- match.arg(method)
  ties_method <- match.arg(ties_method)
  if (!is.null(threshold)) {
    threshold <- validate_probability_threshold(threshold, 'threshold')
  }
  validate_cluster_pairs(pairs, threshold = threshold, method = method)

  source_dataset <- prepare_cluster_source_dataset(
    source_dataset,
    pairs,
    method = method
  )

  # Lazy path: pairs are still in the database
  if (inherits(pairs, 'il_compared_lazy')) {
    return(cluster_lazy(pairs, threshold, method, ties_method, source_dataset))
  }

  if (nrow(pairs) == 0L) {
    return(tibble::tibble(unique_id = character(0), cluster_id = character(0)))
  }

  # Try SQL path first (DuckDB / PostgreSQL)
  model <- attr(pairs, 'model')
  con <- if (!is.null(model)) model$con else NULL
  use_sql <- !is.null(con) &&
    DBI::dbIsValid(con) &&
    detect_dialect(con) %in% c('duckdb', 'postgres')

  if (use_sql) {
    return(cluster_sql(
      con,
      pairs,
      threshold,
      method,
      ties_method,
      source_dataset
    ))
  }

  # Fallback: igraph (works for SQLite or when no connection available)
  cluster_igraph(pairs, threshold, method, ties_method, source_dataset)
}

#' SQL-path clustering (DuckDB/PostgreSQL)
#' @noRd
cluster_sql <- function(
  con,
  pairs,
  threshold,
  method,
  ties_method = 'lowest_id',
  source_dataset = NULL
) {
  cc_prefix <- il_scratch_table_name('cc')
  edges_tbl <- cc_upload_edges(
    con,
    pairs,
    threshold = threshold,
    prefix = cc_prefix
  )
  on.exit(drop_registered(con, edges_tbl), add = TRUE)

  if (method == 'best_link') {
    if (!is.null(source_dataset)) {
      # Iterative one-to-one: merge clusters step-by-step, re-evaluating
      # dataset constraints after each merge (splink's approach).
      result <- solve_one_to_one_sql(
        con,
        edges_tbl,
        source_dataset,
        ties_method,
        prefix = cc_prefix
      )
      # Add isolated nodes
      all_ids <- unique(c(
        as.character(pairs$unique_id_l),
        as.character(pairs$unique_id_r)
      ))
      isolated <- setdiff(all_ids, result$node_id)
      if (length(isolated) > 0L) {
        iso_df <- tibble::tibble(
          node_id = isolated,
          cluster_id = isolated
        )
        result <- rbind(result, iso_df)
      }
      result$cluster_id <- paste0('cluster_', result$cluster_id)
      return(tibble::tibble(
        unique_id = result$node_id,
        cluster_id = result$cluster_id
      ))
    }
    filtered_tbl <- sql_best_link_filter(
      con,
      edges_tbl,
      ties_method,
      prefix = cc_prefix
    )
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {edges_tbl}'))
    DBI::dbExecute(
      con,
      glue::glue(
        'ALTER TABLE {filtered_tbl} RENAME TO {edges_tbl}'
      )
    )
  }

  result <- solve_cc_sql(con, edges_tbl, prefix = cc_prefix)

  # Collect any isolated IDs not in edges (all unique IDs from pairs)
  all_ids <- unique(c(
    as.character(pairs$unique_id_l),
    as.character(pairs$unique_id_r)
  ))
  in_result <- result$node_id
  isolated <- setdiff(all_ids, in_result)

  if (length(isolated) > 0L) {
    iso_df <- tibble::tibble(
      node_id = isolated,
      cluster_id = isolated
    )
    result <- rbind(result, iso_df)
  }

  # Normalise cluster IDs
  result$cluster_id <- paste0('cluster_', result$cluster_id)

  tibble::tibble(
    unique_id = result$node_id,
    cluster_id = result$cluster_id
  )
}

#' igraph-path clustering (fallback for SQLite or no DB connection)
#' @noRd
cluster_igraph <- function(
  pairs,
  threshold,
  method,
  ties_method = 'lowest_id',
  source_dataset = NULL
) {
  all_ids <- unique(c(
    as.character(pairs$unique_id_l),
    as.character(pairs$unique_id_r)
  ))

  if (!is.null(threshold)) {
    pairs <- pairs[which(pairs$match_probability >= threshold), , drop = FALSE]
  }

  if (method == 'best_link') {
    if (!is.null(source_dataset)) {
      # Iterative one-to-one (R fallback)
      return(solve_one_to_one_r(pairs, source_dataset, ties_method))
    }
    pairs <- best_link_filter(pairs, ties_method)
  }

  rlang::check_installed(
    'igraph',
    reason = 'for clustering without a DuckDB or PostgreSQL connection.'
  )

  edges <- data.frame(
    from = as.character(pairs$unique_id_l),
    to = as.character(pairs$unique_id_r),
    stringsAsFactors = FALSE
  )
  g <- igraph::graph_from_data_frame(
    edges,
    directed = FALSE,
    vertices = data.frame(name = all_ids, stringsAsFactors = FALSE)
  )
  comp <- igraph::components(g)
  cluster_map <- paste0('cluster_', comp$membership[all_ids])

  tibble::tibble(
    unique_id = all_ids,
    cluster_id = unname(cluster_map)
  )
}

# Filter edges to keep only mutual best links
# @noRd
best_link_filter <- function(pairs, ties_method = 'lowest_id') {
  if (nrow(pairs) == 0L) {
    return(pairs)
  }
  id_l <- as.character(pairs$unique_id_l)
  id_r <- as.character(pairs$unique_id_r)
  prob <- pairs$match_probability

  all_nodes <- unique(c(id_l, id_r))
  best_prob <- stats::setNames(rep(-Inf, length(all_nodes)), all_nodes)

  for (i in seq_len(nrow(pairs))) {
    if (prob[i] > best_prob[id_l[i]]) {
      best_prob[id_l[i]] <- prob[i]
    }
    if (prob[i] > best_prob[id_r[i]]) best_prob[id_r[i]] <- prob[i]
  }

  if (ties_method == 'drop') {
    # A node is tied if more than one edge shares its best probability.
    # Drop all edges where either endpoint is tied.
    tied_nodes <- character(0)
    for (nd in all_nodes) {
      cnt <- sum(
        (id_l == nd | id_r == nd) & prob == best_prob[nd]
      )
      if (cnt > 1L) tied_nodes <- c(tied_nodes, nd)
    }
    untied <- !((id_l %in% tied_nodes) | (id_r %in% tied_nodes))
    pairs <- pairs[untied, , drop = FALSE]
    if (nrow(pairs) == 0L) {
      return(pairs)
    }
    id_l <- as.character(pairs$unique_id_l)
    id_r <- as.character(pairs$unique_id_r)
    prob <- pairs$match_probability
    # Recompute best_prob on untied pairs
    all_nodes2 <- unique(c(id_l, id_r))
    best_prob2 <- stats::setNames(rep(-Inf, length(all_nodes2)), all_nodes2)
    for (i in seq_len(nrow(pairs))) {
      if (prob[i] > best_prob2[id_l[i]]) {
        best_prob2[id_l[i]] <- prob[i]
      }
      if (prob[i] > best_prob2[id_r[i]]) best_prob2[id_r[i]] <- prob[i]
    }
    keep <- vapply(
      seq_len(nrow(pairs)),
      function(i) {
        prob[i] == best_prob2[id_l[i]] && prob[i] == best_prob2[id_r[i]]
      },
      logical(1)
    )
    return(pairs[keep, , drop = FALSE])
  }

  # 'lowest_id': break ties by keeping the edge to the lower unique_id.
  # For each node track the best edge index; on tie, prefer smaller partner id.
  best_idx <- stats::setNames(rep(NA_integer_, length(all_nodes)), all_nodes)

  for (i in seq_len(nrow(pairs))) {
    for (nd in c(id_l[i], id_r[i])) {
      partner <- if (nd == id_l[i]) id_r[i] else id_l[i]
      prev <- best_idx[nd]
      if (is.na(prev)) {
        best_idx[nd] <- i
      } else {
        prev_prob <- prob[prev]
        prev_partner <- if (nd == id_l[prev]) id_r[prev] else id_l[prev]
        if (
          prob[i] > prev_prob ||
            (prob[i] == prev_prob && partner < prev_partner)
        ) {
          best_idx[nd] <- i
        }
      }
    }
  }

  keep <- vapply(
    seq_len(nrow(pairs)),
    function(i) {
      isTRUE(best_idx[id_l[i]] == i) && isTRUE(best_idx[id_r[i]] == i)
    },
    logical(1)
  )

  pairs[keep, , drop = FALSE]
}

#' Cluster directly from a lazy prediction table (no round-trip)
#' @noRd
cluster_lazy <- function(
  pairs,
  threshold,
  method,
  ties_method = 'lowest_id',
  source_dataset = NULL
) {
  con <- pairs$con
  predicted_tbl <- pairs$predicted_tbl
  cc_prefix <- il_scratch_table_name('cc')

  # Create edges table directly from the predicted table
  edges_tbl <- cc_tbl('edges', cc_prefix)
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {edges_tbl}'))

  threshold_where <- ''
  if (!is.null(threshold)) {
    threshold_where <- glue::glue(' WHERE match_probability >= {threshold}')
  }

  DBI::dbExecute(
    con,
    glue::glue(
      'CREATE TABLE {edges_tbl} AS ',
      'SELECT unique_id_l, unique_id_r, match_probability ',
      'FROM {predicted_tbl}{threshold_where}'
    )
  )
  on.exit(drop_registered(con, edges_tbl), add = TRUE)

  if (method == 'best_link') {
    if (!is.null(source_dataset)) {
      # Iterative one-to-one clustering
      result <- solve_one_to_one_sql(
        con,
        edges_tbl,
        source_dataset,
        ties_method,
        prefix = cc_prefix
      )
      all_ids <- DBI::dbGetQuery(
        con,
        glue::glue(
          'SELECT DISTINCT id FROM (',
          'SELECT unique_id_l AS id FROM {predicted_tbl} ',
          'UNION ',
          'SELECT unique_id_r AS id FROM {predicted_tbl}',
          ') sub'
        )
      )$id

      isolated <- setdiff(all_ids, result$node_id)
      if (length(isolated) > 0L) {
        iso_df <- tibble::tibble(
          node_id = isolated,
          cluster_id = isolated
        )
        result <- rbind(result, iso_df)
      }
      result$cluster_id <- paste0('cluster_', result$cluster_id)
      return(tibble::tibble(
        unique_id = result$node_id,
        cluster_id = result$cluster_id
      ))
    }
    filtered_tbl <- sql_best_link_filter(
      con,
      edges_tbl,
      ties_method,
      prefix = cc_prefix
    )
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {edges_tbl}'))
    DBI::dbExecute(
      con,
      glue::glue(
        'ALTER TABLE {filtered_tbl} RENAME TO {edges_tbl}'
      )
    )
  }

  result <- solve_cc_sql(con, edges_tbl, prefix = cc_prefix)

  # Collect all unique IDs from the predicted table for isolated-node detection
  all_ids <- DBI::dbGetQuery(
    con,
    glue::glue(
      'SELECT DISTINCT id FROM (',
      'SELECT unique_id_l AS id FROM {predicted_tbl} ',
      'UNION ',
      'SELECT unique_id_r AS id FROM {predicted_tbl}',
      ') sub'
    )
  )$id

  in_result <- result$node_id
  isolated <- setdiff(all_ids, in_result)

  if (length(isolated) > 0L) {
    iso_df <- tibble::tibble(
      node_id = isolated,
      cluster_id = isolated
    )
    result <- rbind(result, iso_df)
  }

  result$cluster_id <- paste0('cluster_', result$cluster_id)

  tibble::tibble(
    unique_id = result$node_id,
    cluster_id = result$cluster_id
  )
}

#' Normalise source_dataset argument to a named character vector
#' @noRd
normalise_source_dataset <- function(sd) {
  if (is.null(sd)) {
    return(NULL)
  }
  if (is.data.frame(sd)) {
    if (!all(c('unique_id', 'source_dataset') %in% names(sd))) {
      cli::cli_abort(
        '{.arg source_dataset} data frame must contain columns {.val unique_id} and {.val source_dataset}.'
      )
    }
    if (anyNA(sd$unique_id) || any(sd$unique_id == '')) {
      cli::cli_abort(
        '{.field unique_id} in {.arg source_dataset} must not contain missing values.'
      )
    }
    if (anyNA(sd$source_dataset)) {
      cli::cli_abort(
        '{.field source_dataset} in {.arg source_dataset} must not contain missing values.'
      )
    }
    if (anyDuplicated(sd$unique_id) > 0L) {
      cli::cli_abort(
        '{.arg source_dataset} must map each {.field unique_id} at most once.'
      )
    }
    out <- as.character(sd$source_dataset)
    names(out) <- as.character(sd$unique_id)
    return(out)
  }
  if (is.character(sd) && !is.null(names(sd))) {
    if (anyNA(names(sd)) || any(names(sd) == '')) {
      cli::cli_abort(
        '{.arg source_dataset} must have a non-missing name for every mapping.'
      )
    }
    if (anyNA(sd)) {
      cli::cli_abort(
        '{.arg source_dataset} must not contain missing source-dataset values.'
      )
    }
    if (anyDuplicated(names(sd)) > 0L) {
      cli::cli_abort(
        '{.arg source_dataset} must map each {.field unique_id} at most once.'
      )
    }
    return(sd)
  }
  cli::cli_abort(
    '{.arg source_dataset} must be a named character vector or a data frame with columns {.val unique_id} and {.val source_dataset}.'
  )
}

#' Validate public clustering input columns
#' @noRd
validate_cluster_pairs <- function(
  pairs,
  threshold = NULL,
  method = c('connected', 'best_link')
) {
  method <- match.arg(method)

  if (!inherits(pairs, 'il_compared_lazy') && !is.data.frame(pairs)) {
    cli::cli_abort(
      '{.arg pairs} must be a data frame, tibble, or {.cls il_compared_lazy} object.'
    )
  }

  required_cols <- c('unique_id_l', 'unique_id_r')
  if (!is.null(threshold) || identical(method, 'best_link')) {
    required_cols <- c(required_cols, 'match_probability')
  }
  validate_pair_input_columns(pairs, required_cols)
  invisible(pairs)
}

#' Validate required columns on collected or lazy pair inputs
#' @noRd
validate_pair_input_columns <- function(pairs, required_cols, arg = 'pairs') {
  cols <- pair_input_columns(pairs)
  missing_cols <- setdiff(required_cols, cols)
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      '{.arg {arg}} must contain column{?s} {.field {missing_cols}}.'
    )
  }
  invisible(pairs)
}

#' Return available columns for collected or lazy pair inputs
#' @noRd
pair_input_columns <- function(pairs) {
  if (inherits(pairs, 'il_compared_lazy')) {
    return(DBI::dbListFields(pairs$con, pairs$predicted_tbl))
  }
  if (!is.data.frame(pairs)) {
    cli::cli_abort(
      '{.arg pairs} must be a data frame, tibble, or {.cls il_compared_lazy} object.'
    )
  }
  names(pairs)
}

#' Validate and normalise source-dataset mappings
#' @noRd
prepare_cluster_source_dataset <- function(source_dataset, pairs, method) {
  source_dataset <- normalise_source_dataset(source_dataset)

  if (!is.null(source_dataset) && method != 'best_link') {
    cli::cli_warn(
      '{.arg source_dataset} is only used with {.code method = "best_link"}. Ignoring.'
    )
    return(NULL)
  }

  if (is.null(source_dataset)) {
    return(NULL)
  }

  all_ids <- cluster_input_ids(pairs)
  missing_ids <- setdiff(all_ids, names(source_dataset))
  if (length(missing_ids) > 0L) {
    preview <- missing_ids[seq_len(min(5L, length(missing_ids)))]
    extra <- length(missing_ids) - length(preview)
    extra_text <- if (extra > 0L) paste0(' and ', extra, ' more') else ''
    cli::cli_abort(
      '{.arg source_dataset} must provide a source dataset for every {.field unique_id} in {.arg pairs}. Missing source-dataset entries for {.val {preview}}{extra_text}.'
    )
  }

  source_dataset
}

#' Return all unique IDs present in collected or lazy pair inputs
#' @noRd
cluster_input_ids <- function(pairs) {
  if (inherits(pairs, 'il_compared_lazy')) {
    return(
      DBI::dbGetQuery(
        pairs$con,
        glue::glue(
          'SELECT DISTINCT id FROM (',
          'SELECT unique_id_l AS id FROM {pairs$predicted_tbl} ',
          'UNION ',
          'SELECT unique_id_r AS id FROM {pairs$predicted_tbl}',
          ') sub'
        )
      )$id
    )
  }

  unique(c(
    as.character(pairs$unique_id_l),
    as.character(pairs$unique_id_r)
  ))
}

#' Validate cluster-assignment inputs
#' @noRd
validate_cluster_assignments <- function(clusters, arg = 'clusters') {
  if (!is.data.frame(clusters)) {
    cli::cli_abort('{.arg {arg}} must be a data frame or tibble.')
  }

  required_cols <- c('unique_id', 'cluster_id')
  missing_cols <- setdiff(required_cols, names(clusters))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      '{.arg {arg}} must contain column{?s} {.field {missing_cols}}.'
    )
  }
  if (anyNA(clusters$unique_id) || anyNA(clusters$cluster_id)) {
    cli::cli_abort(
      '{.arg {arg}} must not contain missing {.field unique_id} or {.field cluster_id} values.'
    )
  }
  if (anyDuplicated(clusters$unique_id) > 0L) {
    cli::cli_abort('{.arg {arg}} must contain one row per {.field unique_id}.')
  }

  invisible(clusters)
}
