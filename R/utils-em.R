# Internal helpers for the EM algorithm and parameter estimation.

#' Get pairs with pre-computed gamma columns
#'
#' For DuckDB: runs a single SQL query that computes gammas in-database.
#' For SQLite: falls back to pulling pairs and computing gammas in R.
#'
#' @param model An il_model object.
#' @param blocking_rules List of blocking rule objects.
#' @param limit Optional integer pair limit.
#' @return A list with `ids` (data.frame of l/r unique_id) and `gamma_mat`
#'   (integer matrix of gamma values).
#' @noRd
get_pairs_with_gammas <- function(model, blocking_rules, limit = NULL) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  tf_cols <- tf_columns(comparisons)

  if (dialect_has_fuzzy_sql(dialect)) {
    sql <- build_gamma_query(model, blocking_rules, limit = limit)
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0L) {
      return(list(
        ids = data.frame(
          l_unique_id = integer(0), r_unique_id = integer(0)
        ),
        gamma_mat = matrix(0L,
          nrow = 0, ncol = length(comp_names),
          dimnames = list(NULL, comp_names)
        ),
        tf_data = NULL
      ))
    }
    ids <- result[, c('l_unique_id', 'r_unique_id'), drop = FALSE]
    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names

    # Extract TF data if present
    tf_data <- NULL
    if (length(tf_cols) > 0L) {
      tf_col_names <- c(
        paste0('tf_', tf_cols, '_l'),
        paste0('tf_', tf_cols, '_r')
      )
      present <- intersect(tf_col_names, names(result))
      if (length(present) > 0L) {
        tf_data <- result[, present, drop = FALSE]
      }
    }

    return(list(ids = ids, gamma_mat = gamma_mat, tf_data = tf_data))
  }

  # Fallback: pull pairs, compute gammas in R
  all_pairs <- list()
  for (br in blocking_rules) {
    bp <- get_blocked_pairs(model, br)
    if (nrow(bp) > 0L) all_pairs <- c(all_pairs, list(bp))
  }
  if (length(all_pairs) == 0L) {
    return(list(
      ids = data.frame(
        l_unique_id = integer(0), r_unique_id = integer(0)
      ),
      gamma_mat = matrix(0L,
        nrow = 0, ncol = length(comp_names),
        dimnames = list(NULL, comp_names)
      ),
      tf_data = NULL
    ))
  }
  pairs <- do.call(rbind, all_pairs)
  pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = '||')
  pairs <- pairs[!duplicated(pair_key), , drop = FALSE]
  if (!is.null(limit) && nrow(pairs) > limit) {
    pairs <- pairs[seq_len(limit), , drop = FALSE]
  }
  ids <- data.frame(
    l_unique_id = pairs$l_unique_id,
    r_unique_id = pairs$r_unique_id
  )
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  # R-side TF lookup
  tf_data <- NULL
  if (length(tf_cols) > 0L) {
    tf_data <- lookup_tf_r(model, pairs, tf_cols)
  }

  list(ids = ids, gamma_mat = gamma_mat, tf_data = tf_data)
}

#' Get random pairs with gammas (for u estimation)
#'
#' @param model An il_model object.
#' @param max_pairs Maximum pairs to sample.
#' @return Same structure as get_pairs_with_gammas().
#' @noRd
get_random_pairs_with_gammas <- function(model, max_pairs = 1e6) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))

  if (dialect_has_fuzzy_sql(dialect)) {
    tbl_l <- model$data$tbl_l
    tbl_r <- if (!is.null(model$data$tbl_r)) model$data$tbl_r else tbl_l
    link_type <- model$link_type %||% 'dedupe'
    has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l
    max_pairs <- as.integer(max_pairs)

    gamma_exprs <- vapply(comparisons, function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue('{expr} AS gamma_{comp$columns}')
    }, character(1))
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
    parts <- vapply(table_pairs, function(tp) {
      glue::glue(
        'SELECT l.unique_id AS l_unique_id, r.unique_id AS r_unique_id, ',
        '{gamma_select} ',
        'FROM {tp$from_l} l, {tp$from_r} r ',
        'WHERE {tp$join_cond}'
      )
    }, character(1))
    inner <- paste(parts, collapse = ' UNION ')

    sql <- glue::glue(
      'SELECT DISTINCT * FROM ({inner}) AS pairs LIMIT {max_pairs}'
    )
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0L) {
      return(list(
        ids = data.frame(
          l_unique_id = integer(0), r_unique_id = integer(0)
        ),
        gamma_mat = matrix(0L,
          nrow = 0, ncol = length(comp_names),
          dimnames = list(NULL, comp_names)
        )
      ))
    }
    ids <- result[, c('l_unique_id', 'r_unique_id'), drop = FALSE]
    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names
    return(list(ids = ids, gamma_mat = gamma_mat))
  }

  # Fallback: R-side
  pairs <- get_all_pairs(model, max_pairs = max_pairs)
  if (nrow(pairs) == 0L) {
    return(list(
      ids = data.frame(
        l_unique_id = integer(0), r_unique_id = integer(0)
      ),
      gamma_mat = matrix(0L,
        nrow = 0, ncol = length(comp_names),
        dimnames = list(NULL, comp_names)
      )
    ))
  }
  ids <- data.frame(
    l_unique_id = pairs$l_unique_id,
    r_unique_id = pairs$r_unique_id
  )
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  list(ids = ids, gamma_mat = gamma_mat)
}

#' Compute binary comparison level (gamma) for a pair of values
#' @param val_l Left record values (vector).
#' @param val_r Right record values (vector).
#' @param comp_level An il_comparison_level object.
#' @return Integer vector: 1 = match, 0 = non-match.
#' @noRd
compute_gamma <- function(val_l, val_r, comp_level) {
  method <- comp_level$method
  n <- length(val_l)
  both_present <- !is.na(val_l) & !is.na(val_r)

  if (method == 'exact') {
    return(ifelse(both_present & val_l == val_r, 1L, 0L))
  }

  if (method %in% c('levenshtein', 'damerau_levenshtein')) {
    threshold <- comp_level$thresholds[1]
    dist <- rep(NA_real_, n)
    dist[both_present] <- stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = 'lv'
    )
    return(ifelse(both_present & !is.na(dist) & dist <= threshold, 1L, 0L))
  }

  if (method %in% c('jaro_winkler', 'jaro')) {
    threshold <- comp_level$thresholds[1]
    p <- if (method == 'jaro_winkler') 0.1 else 0
    score <- rep(NA_real_, n)
    score[both_present] <- 1 - stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = 'jw', p = p
    )
    return(ifelse(both_present & !is.na(score) & score >= threshold, 1L, 0L))
  }

  if (method %in% c('jaccard', 'cosine')) {
    threshold <- comp_level$thresholds[1]
    sd_method <- if (method == 'jaccard') 'jaccard' else 'cosine'
    score <- rep(NA_real_, n)
    score[both_present] <- 1 - stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = sd_method, q = 2
    )
    return(ifelse(both_present & !is.na(score) & score >= threshold, 1L, 0L))
  }

  if (method %in% c('numeric_diff', 'pct_diff')) {
    threshold <- comp_level$thresholds[1]
    num_l <- suppressWarnings(as.numeric(val_l))
    num_r <- suppressWarnings(as.numeric(val_r))
    bp <- !is.na(num_l) & !is.na(num_r)
    if (method == 'numeric_diff') {
      diff <- abs(num_l - num_r)
    } else {
      denom <- pmax(abs(num_l), abs(num_r))
      denom[denom == 0] <- NA_real_
      diff <- abs(num_l - num_r) / denom
    }
    return(ifelse(bp & !is.na(diff) & diff <= threshold, 1L, 0L))
  }

  if (method == 'date_diff') {
    threshold_days <- comp_level$thresholds[1]
    unit <- comp_level$units[1]
    mult <- switch(unit,
      'days' = 1,
      'months' = 30,
      'years' = 365,
      1
    )
    days_thresh <- threshold_days * mult
    date_l <- suppressWarnings(as.Date(val_l))
    date_r <- suppressWarnings(as.Date(val_r))
    bp <- !is.na(date_l) & !is.na(date_r)
    diff <- abs(as.numeric(date_l - date_r))
    return(ifelse(bp & !is.na(diff) & diff <= days_thresh, 1L, 0L))
  }

  if (method == 'levels') {
    # Use the first non-null, non-else level for matching
    for (sublevel in comp_level$levels) {
      if (!isTRUE(sublevel$is_null_level) && !isTRUE(sublevel$is_else_level)) {
        return(compute_gamma(val_l, val_r, sublevel))
      }
    }
  }

  # Fallback: exact match
  ifelse(both_present & val_l == val_r, 1L, 0L)
}

#' Get blocked pairs from the database as a data frame
#' @param model An il_model object.
#' @param blocking An il_blocking_rule object.
#' @return A data frame with columns from both left and right records.
#' @noRd
get_blocked_pairs <- function(model, blocking) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- if (!is.null(model$data$tbl_r)) model$data$tbl_r else tbl_l
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

  cols <- model$data$columns
  sel <- build_select_aliases(cols)
  block_where <- build_blocking_condition(blocking$columns, blocking$where)

  table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
  parts <- vapply(table_pairs, function(tp) {
    where_clause <- if (nzchar(block_where)) {
      glue::glue('{tp$join_cond} AND {block_where}')
    } else {
      tp$join_cond
    }
    glue::glue(
      'SELECT {sel$left}, {sel$right} FROM {tp$from_l} l, {tp$from_r} r ',
      'WHERE {where_clause}'
    )
  }, character(1))
  sql <- paste(parts, collapse = ' UNION ')

  DBI::dbGetQuery(con, sql)
}

#' Get all pairs (no blocking) from the database
#' @noRd
get_all_pairs <- function(model, max_pairs = 1e6) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- if (!is.null(model$data$tbl_r)) model$data$tbl_r else tbl_l
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

  cols <- model$data$columns
  sel <- build_select_aliases(cols)

  max_pairs <- as.integer(max_pairs)
  table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
  parts <- vapply(table_pairs, function(tp) {
    glue::glue(
      'SELECT {sel$left}, {sel$right} FROM {tp$from_l} l, {tp$from_r} r ',
      'WHERE {tp$join_cond}'
    )
  }, character(1))
  sql <- paste(parts, collapse = ' UNION ')
  sql <- glue::glue('{sql} LIMIT {max_pairs}')

  DBI::dbGetQuery(con, sql)
}

#' Compute gamma matrix for pairs
#' @param pairs Data frame of pairs.
#' @param comparisons List of comparison entries from spec.
#' @return An integer matrix (n_pairs x n_comparisons).
#' @noRd
compute_gamma_matrix <- function(pairs, comparisons) {
  n_comp <- length(comparisons)
  n_pairs <- nrow(pairs)

  gamma_mat <- matrix(0L, nrow = n_pairs, ncol = n_comp)

  for (j in seq_len(n_comp)) {
    comp <- comparisons[[j]]
    col <- comp$columns
    val_l <- pairs[[paste0('l_', col)]]
    val_r <- pairs[[paste0('r_', col)]]
    gamma_mat[, j] <- compute_gamma(val_l, val_r, comp$method)
  }

  colnames(gamma_mat) <- vapply(comparisons, function(c) c$columns, character(1))
  gamma_mat
}
