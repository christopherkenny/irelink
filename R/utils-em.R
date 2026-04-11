# Internal helpers for the EM algorithm and parameter estimation.

#' Get aggregated gamma-pattern counts from blocked pairs
#'
#' Returns unique gamma patterns with their frequency counts, keeping
#' the data transfer from database to R minimal.  Used by
#' [il_estimate_em()] so it never needs the full pair-level matrix.
#'
#' @param model An il_model object.
#' @param blocking_rules List of blocking rule objects.
#' @param limit Optional integer pair limit.
#' @return A list with `counts` (data frame of gamma columns + `n`) and
#'   `n_pairs` (total pairs).
#' @noRd
get_pairs_with_gamma_counts <- function(model, blocking_rules, limit = NULL) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  gamma_cols <- paste0('gamma_', comp_names)

  if (dialect_has_fuzzy_sql(dialect)) {
    gamma_sql <- build_gamma_query(model, blocking_rules, limit = limit)
    group_by_clause <- paste(gamma_cols, collapse = ', ')
    sql <- glue::glue(
      'SELECT {group_by_clause}, COUNT(*) AS n FROM ({gamma_sql}) AS pairs ',
      'GROUP BY {group_by_clause}'
    )
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0L) {
      return(list(counts = result, n_pairs = 0L))
    }
    return(list(counts = result, n_pairs = sum(result$n)))
  }

  # Fallback: pull pairs, compute gammas, aggregate counts in R
  all_pairs <- list()
  for (br in blocking_rules) {
    bp <- get_blocked_pairs(model, br)
    if (nrow(bp) > 0L) all_pairs <- c(all_pairs, list(bp))
  }
  if (length(all_pairs) == 0L) {
    empty <- as.data.frame(matrix(
      integer(0), nrow = 0, ncol = length(gamma_cols) + 1L,
      dimnames = list(NULL, c(gamma_cols, 'n'))
    ))
    return(list(counts = empty, n_pairs = 0L))
  }
  pairs <- do.call(rbind, all_pairs)
  pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = '||')
  pairs <- pairs[!duplicated(pair_key), , drop = FALSE]
  if (!is.null(limit) && nrow(pairs) > limit) {
    pairs <- pairs[seq_len(limit), , drop = FALSE]
  }
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  n_pairs <- nrow(gamma_mat)
  counts_df <- as.data.frame(gamma_mat)
  names(counts_df) <- gamma_cols
  counts <- stats::aggregate(list(n = rep(1L, n_pairs)), by = counts_df, FUN = sum)
  list(counts = counts, n_pairs = n_pairs)
}

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
#' Returns gamma-level counts aggregated across a random sample of pairs,
#' rather than the full pair matrix, to keep data transfer small.
#'
#' @param model An il_model object.
#' @param max_pairs Maximum pairs to sample.
#' @return A list with `counts` (data frame of gamma columns + `n`) and
#'   `n_pairs` (total sampled pairs).
#' @noRd
get_random_pairs_with_gammas <- function(model, max_pairs = 1e6) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  gamma_cols <- paste0('gamma_', comp_names)

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
    group_by_clause <- paste(gamma_cols, collapse = ', ')

    table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
    parts <- vapply(table_pairs, function(tp) {
      glue::glue(
        'SELECT {gamma_select} ',
        'FROM {tp$from_l} l, {tp$from_r} r ',
        'WHERE {tp$join_cond}'
      )
    }, character(1))
    inner <- paste(parts, collapse = ' UNION ALL ')

    sql <- glue::glue(
      'SELECT {group_by_clause}, COUNT(*) AS n FROM (',
      'SELECT * FROM ({inner}) AS pairs LIMIT {max_pairs}',
      ') AS sampled GROUP BY {group_by_clause}'
    )
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0L) {
      return(list(counts = result, n_pairs = 0L))
    }
    return(list(counts = result, n_pairs = sum(result$n)))
  }

  # Fallback: R-side — pull pairs, compute gammas, aggregate counts in R
  pairs <- get_all_pairs(model, max_pairs = max_pairs)
  if (nrow(pairs) == 0L) {
    empty <- as.data.frame(matrix(
      integer(0), nrow = 0, ncol = length(gamma_cols) + 1L,
      dimnames = list(NULL, c(gamma_cols, 'n'))
    ))
    return(list(counts = empty, n_pairs = 0L))
  }
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  n_pairs <- nrow(gamma_mat)
  counts_df <- as.data.frame(gamma_mat)
  names(counts_df) <- gamma_cols
  counts <- stats::aggregate(list(n = rep(1L, n_pairs)), by = counts_df, FUN = sum)
  list(counts = counts, n_pairs = n_pairs)
}

#' Compute multi-level gamma for a pair of values
#' @param val_l Left record values (vector).
#' @param val_r Right record values (vector).
#' @param comp_level An il_comparison_level object.
#' @return Integer vector: 0 (else) through K (best match).
#' @noRd
compute_gamma <- function(val_l, val_r, comp_level) {
  method <- comp_level$method
  n <- length(val_l)
  both_present <- !is.na(val_l) & !is.na(val_r)

  if (method == 'exact') {
    return(ifelse(both_present & val_l == val_r, 1L, 0L))
  }

  # Multi-threshold: loop from most lenient to strictest, overwriting
  # with higher gamma levels. Thresholds are stored strictest-first.
  thresholds <- comp_level$thresholds

  if (method %in% c('levenshtein', 'damerau_levenshtein')) {
    dist <- rep(NA_real_, n)
    dist[both_present] <- stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = 'lv'
    )
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[both_present & !is.na(dist) & dist <= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method %in% c('jaro_winkler', 'jaro')) {
    p <- if (method == 'jaro_winkler') 0.1 else 0
    score <- rep(NA_real_, n)
    score[both_present] <- 1 - stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = 'jw', p = p
    )
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[both_present & !is.na(score) & score >= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method %in% c('jaccard', 'cosine')) {
    sd_method <- if (method == 'jaccard') 'jaccard' else 'cosine'
    score <- rep(NA_real_, n)
    score[both_present] <- 1 - stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = sd_method, q = 2
    )
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[both_present & !is.na(score) & score >= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method %in% c('numeric_diff', 'pct_diff')) {
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
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[bp & !is.na(diff) & diff <= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method == 'date_diff') {
    date_l <- suppressWarnings(as.Date(val_l))
    date_r <- suppressWarnings(as.Date(val_r))
    bp <- !is.na(date_l) & !is.na(date_r)
    diff <- abs(as.numeric(date_l - date_r))
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      unit <- comp_level$units[i]
      mult <- switch(unit,
        'days' = 1,
        'months' = 30,
        'years' = 365,
        1
      )
      days_thresh <- thresholds[i] * mult
      level_code <- nt - i + 1L
      gamma[bp & !is.na(diff) & diff <= days_thresh] <- level_code
    }
    return(gamma)
  }

  if (method == 'time_diff') {
    ts_l <- suppressWarnings(as.POSIXct(val_l))
    ts_r <- suppressWarnings(as.POSIXct(val_r))
    bp <- !is.na(ts_l) & !is.na(ts_r)
    diff_secs <- abs(as.numeric(difftime(ts_l, ts_r, units = 'secs')))
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      secs_thresh <- time_diff_to_seconds(thresholds[i], comp_level$units[i])
      level_code <- nt - i + 1L
      gamma[bp & !is.na(diff_secs) & diff_secs <= secs_thresh] <- level_code
    }
    return(gamma)
  }

  if (method == 'soundex') {
    sx_l <- il_soundex(as.character(val_l))
    sx_r <- il_soundex(as.character(val_r))
    return(ifelse(both_present & !is.na(sx_l) & !is.na(sx_r) & sx_l == sx_r, 1L, 0L))
  }

  if (method == 'array_min_distance') {
    fn <- comp_level$fn
    thresholds <- comp_level$thresholds
    n <- length(thresholds)
    sd_method <- if (fn == 'jaro_winkler') 'jw' else 'lv'
    sd_p <- if (fn == 'jaro_winkler') 0.1 else 0

    gamma <- rep(0L, length(val_l))
    for (k in seq_len(length(val_l))) {
      if (is.na(val_l[k]) || is.na(val_r[k])) next
      a <- unique(trimws(unlist(strsplit(as.character(val_l[k]), ',', fixed = TRUE))))
      b <- unique(trimws(unlist(strsplit(as.character(val_r[k]), ',', fixed = TRUE))))
      pairs_a <- rep(a, each = length(b))
      pairs_b <- rep(b, times = length(a))
      dists <- stringdist::stringdist(pairs_a, pairs_b, method = sd_method, p = sd_p)
      best <- if (fn == 'jaro_winkler') max(1 - dists) else min(dists)
      # Iterate most-lenient to strictest; overwrite with higher gamma each time
      # a stricter threshold is also satisfied. Matches the pattern in jaro_winkler
      # and levenshtein handling above.
      for (i in rev(seq_along(thresholds))) {
        level_code <- n - i + 1L
        passes <- if (fn == 'jaro_winkler') {
          best >= thresholds[i]
        } else {
          best <= thresholds[i]
        }
        if (passes) {
          gamma[k] <- level_code
        }
      }
    }
    return(gamma)
  }

  if (method == 'array_subset') {
    result <- mapply(function(a, b) {
      if (is.na(a) || is.na(b)) {
        return(0L)
      }
      a_set <- unique(unlist(strsplit(as.character(a), ',\\s*')))
      b_set <- unique(unlist(strsplit(as.character(b), ',\\s*')))
      if (all(a_set %in% b_set) || all(b_set %in% a_set)) 1L else 0L
    }, val_l, val_r)
    return(as.integer(result))
  }

  if (method == 'levels') {
    # Check sublevels from best to worst (skip null/else)
    sublevels <- Filter(function(l) {
      !isTRUE(l$is_null_level) && !isTRUE(l$is_else_level)
    }, comp_level$levels)
    nsub <- length(sublevels)
    if (nsub == 0L) {
      return(ifelse(both_present & val_l == val_r, 1L, 0L))
    }
    gamma <- rep(0L, n)
    for (i in rev(seq_along(sublevels))) {
      sub_gamma <- compute_gamma(val_l, val_r, sublevels[[i]])
      level_code <- nsub - i + 1L
      gamma[sub_gamma > 0L] <- level_code
    }
    return(gamma)
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
  block_where <- build_blocking_condition(blocking$columns, blocking$where,
    transform = blocking$transform,
    dialect = detect_dialect(con)
  )

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
    # Apply transform if specified
    if (!is.null(comp$transform)) {
      val_l <- comp$transform(val_l)
      val_r <- comp$transform(val_r)
    }
    gamma_mat[, j] <- compute_gamma(val_l, val_r, comp$method)
  }

  colnames(gamma_mat) <- vapply(comparisons, function(c) c$columns, character(1))
  gamma_mat
}
