# Internal helpers for the EM algorithm and parameter estimation.

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

  if (method == "exact") {
    return(ifelse(both_present & val_l == val_r, 1L, 0L))
  }

  if (method %in% c("levenshtein", "damerau_levenshtein")) {
    threshold <- comp_level$thresholds[1]
    dist <- rep(NA_real_, n)
    dist[both_present] <- stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = "lv"
    )
    return(ifelse(both_present & !is.na(dist) & dist <= threshold, 1L, 0L))
  }

  if (method %in% c("jaro_winkler", "jaro")) {
    threshold <- comp_level$thresholds[1]
    p <- if (method == "jaro_winkler") 0.1 else 0
    score <- rep(NA_real_, n)
    score[both_present] <- 1 - stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = "jw", p = p
    )
    return(ifelse(both_present & !is.na(score) & score >= threshold, 1L, 0L))
  }

  if (method %in% c("jaccard", "cosine")) {
    threshold <- comp_level$thresholds[1]
    sd_method <- if (method == "jaccard") "jaccard" else "cosine"
    score <- rep(NA_real_, n)
    score[both_present] <- 1 - stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = sd_method, q = 2
    )
    return(ifelse(both_present & !is.na(score) & score >= threshold, 1L, 0L))
  }

  if (method %in% c("numeric_diff", "pct_diff")) {
    threshold <- comp_level$thresholds[1]
    num_l <- suppressWarnings(as.numeric(val_l))
    num_r <- suppressWarnings(as.numeric(val_r))
    bp <- !is.na(num_l) & !is.na(num_r)
    if (method == "numeric_diff") {
      diff <- abs(num_l - num_r)
    } else {
      denom <- pmax(abs(num_l), abs(num_r))
      denom[denom == 0] <- NA_real_
      diff <- abs(num_l - num_r) / denom
    }
    return(ifelse(bp & !is.na(diff) & diff <= threshold, 1L, 0L))
  }

  if (method == "date_diff") {
    threshold_days <- comp_level$thresholds[1]
    unit <- comp_level$units[1]
    mult <- switch(unit, "days" = 1, "months" = 30, "years" = 365, 1)
    days_thresh <- threshold_days * mult
    date_l <- suppressWarnings(as.Date(val_l))
    date_r <- suppressWarnings(as.Date(val_r))
    bp <- !is.na(date_l) & !is.na(date_r)
    diff <- abs(as.numeric(date_l - date_r))
    return(ifelse(bp & !is.na(diff) & diff <= days_thresh, 1L, 0L))
  }

  if (method == "levels") {
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

  cols <- model$data$columns
  sel <- build_select_aliases(cols)
  block_where <- build_blocking_condition(blocking$columns)

  if (is.null(model$data$tbl_r) || model$data$tbl_r == tbl_l) {
    dedup_cond <- "l.rowid < r.rowid"
    sql <- glue::glue(
      "SELECT {sel$left}, {sel$right} FROM {tbl_l} l, {tbl_r} r ",
      "WHERE {dedup_cond} AND {block_where}"
    )
  } else {
    sql <- glue::glue(
      "SELECT {sel$left}, {sel$right} FROM {tbl_l} l, {tbl_r} r ",
      "WHERE {block_where}"
    )
  }

  DBI::dbGetQuery(con, sql)
}

#' Get all pairs (no blocking) from the database
#' @noRd
get_all_pairs <- function(model, max_pairs = 1e6) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- if (!is.null(model$data$tbl_r)) model$data$tbl_r else tbl_l

  cols <- model$data$columns
  sel <- build_select_aliases(cols)

  max_pairs <- as.integer(max_pairs)
  if (is.null(model$data$tbl_r) || model$data$tbl_r == tbl_l) {
    sql <- glue::glue(
      "SELECT {sel$left}, {sel$right} FROM {tbl_l} l, {tbl_r} r ",
      "WHERE l.rowid < r.rowid LIMIT {max_pairs}"
    )
  } else {
    sql <- glue::glue(
      "SELECT {sel$left}, {sel$right} FROM {tbl_l} l, {tbl_r} r ",
      "LIMIT {max_pairs}"
    )
  }

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
    val_l <- pairs[[paste0("l_", col)]]
    val_r <- pairs[[paste0("r_", col)]]
    gamma_mat[, j] <- compute_gamma(val_l, val_r, comp$method)
  }

  colnames(gamma_mat) <- vapply(comparisons, function(c) c$columns, character(1))
  gamma_mat
}
