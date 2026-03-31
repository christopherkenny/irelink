# Term frequency computation and adjustment helpers.
# Implements the TF weighting from Fellegi-Sunter: rare exact-match values
# receive higher match weights than common ones.

#' Identify comparison columns that have term_frequency enabled
#' @param comparisons List of comparison entries from the spec.
#' @return Character vector of column names with TF enabled.
#' @noRd
tf_columns <- function(comparisons) {
  cols <- character(0)
  for (comp in comparisons) {
    if (isTRUE(comp$method$term_frequency)) {
      cols <- c(cols, comp$columns)
    }
  }
  unique(cols)
}

#' Compute and store term frequency lookup tables in the database
#'
#' For each comparison with `term_frequency = TRUE`, creates a table
#' `__il_tf_<col>` containing `(<col>, tf_<col>)` where `tf_<col>` is the
#' proportion of non-NULL records with that value.
#'
#' @param model An il_model object (with data already uploaded).
#' @return The model, with `model$data$tf_tables` populated.
#' @noRd
compute_tf_tables <- function(model) {
  comparisons <- model$spec$comparisons
  tf_cols <- tf_columns(comparisons)

  if (length(tf_cols) == 0L) {
    return(model)
  }

  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r

  tf_tables <- list()
  for (col in tf_cols) {
    tf_tbl <- paste0('__il_tf_', col)

    if (!is.null(tbl_r)) {
      # Link mode: compute from union of both tables
      union_sql <- glue::glue(
        'SELECT {col} FROM {tbl_l} WHERE {col} IS NOT NULL ',
        'UNION ALL ',
        'SELECT {col} FROM {tbl_r} WHERE {col} IS NOT NULL'
      )
      select_sql <- glue::glue(
        'SELECT {col}, CAST(COUNT(*) AS DOUBLE) / ',
        '(SELECT COUNT(*) FROM ({union_sql}) sub) AS tf_{col} ',
        'FROM ({union_sql}) combined ',
        'GROUP BY {col}'
      )
    } else {
      # Dedupe mode: single table
      select_sql <- glue::glue(
        'SELECT {col}, CAST(COUNT(*) AS DOUBLE) / ',
        '(SELECT COUNT({col}) FROM {tbl_l} WHERE {col} IS NOT NULL) AS tf_{col} ',
        'FROM {tbl_l} ',
        'WHERE {col} IS NOT NULL ',
        'GROUP BY {col}'
      )
    }

    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tf_tbl}'))
    DBI::dbExecute(con, glue::glue('CREATE TABLE {tf_tbl} AS {select_sql}'))
    tf_tables[[col]] <- tf_tbl
  }

  model$data$tf_tables <- tf_tables
  model
}

#' Generate SQL SELECT expressions for term frequency columns
#'
#' Produces scalar subqueries that look up TF values for left and right
#' records from the pre-computed `__il_tf_<col>` tables.
#'
#' @param tf_cols Character vector of column names with TF enabled.
#' @return A SQL fragment for the SELECT clause, or NULL if no TF columns.
#' @noRd
sql_tf_select_exprs <- function(tf_cols) {
  if (length(tf_cols) == 0L) {
    return(NULL)
  }
  exprs <- character(0)
  for (col in tf_cols) {
    tf_tbl <- paste0('__il_tf_', col)
    exprs <- c(
      exprs,
      glue::glue(
        '(SELECT tf_{col} FROM {tf_tbl} WHERE {col} = l.{col}) AS tf_{col}_l'
      ),
      glue::glue(
        '(SELECT tf_{col} FROM {tf_tbl} WHERE {col} = r.{col}) AS tf_{col}_r'
      )
    )
  }
  paste(exprs, collapse = ', ')
}

#' Compute TF adjustment vector for match weights
#'
#' For each pair, adds `log2(u_exact / max(tf_l, tf_r))` to the match weight
#' when gamma equals the highest level (exact match) and TF is enabled for
#' that comparison. Following splink, this effectively replaces the global
#' u-probability with the value-specific frequency.
#'
#' @param gamma_mat Integer matrix (n_pairs x n_comparisons).
#' @param tf_data Data frame with `tf_<col>_l` and `tf_<col>_r` columns.
#' @param comparisons List of comparison entries from the spec.
#' @param mu List of m/u from `extract_mu_vectors()`.
#' @return Numeric vector of TF adjustments (length = nrow(gamma_mat)).
#' @noRd
compute_tf_adjustment <- function(gamma_mat, tf_data, comparisons, mu) {
  n_pairs <- nrow(gamma_mat)
  if (n_pairs == 0L) {
    return(numeric(0))
  }

  adjustment <- numeric(n_pairs)

  for (j in seq_along(comparisons)) {
    comp <- comparisons[[j]]
    col <- comp$columns

    if (!isTRUE(comp$method$term_frequency)) next

    tf_l <- tf_data[[paste0('tf_', col, '_l')]]
    tf_r <- tf_data[[paste0('tf_', col, '_r')]]

    if (is.null(tf_l) || is.null(tf_r)) next

    # Use maximum of left/right TF values (following splink)
    tf_max <- pmax(tf_l, tf_r, na.rm = TRUE)

    # TF applies at the highest gamma level (exact match)
    max_level <- n_gamma_levels(comp$method) - 1L
    u_exact <- mu$u_levels[[col]][max_level + 1L]

    mask <- gamma_mat[, j] == max_level & !is.na(tf_max) & tf_max > 0
    if (any(mask)) {
      adjustment[mask] <- adjustment[mask] +
        log2(pmax(u_exact, 1e-10) / tf_max[mask])
    }
  }

  adjustment
}

#' Compute per-comparison TF adjustment for each pair
#'
#' Returns a list of per-comparison TF adjustments for storage in the
#' result tibble and use by the waterfall.
#'
#' @param gamma_mat Integer matrix (n_pairs x n_comparisons).
#' @param tf_data Data frame with TF columns.
#' @param comparisons List of comparison entries from the spec.
#' @param mu List of m/u from `extract_mu_vectors()`.
#' @return A named list of numeric vectors (one per TF comparison), or NULL.
#' @noRd
compute_tf_adjustment_matrix <- function(gamma_mat, tf_data, comparisons, mu) {
  tf_cols <- tf_columns(comparisons)
  if (length(tf_cols) == 0L) {
    return(NULL)
  }

  n_pairs <- nrow(gamma_mat)
  adj_list <- list()

  for (j in seq_along(comparisons)) {
    comp <- comparisons[[j]]
    col <- comp$columns

    if (!isTRUE(comp$method$term_frequency)) next

    adj <- numeric(n_pairs)
    tf_l <- tf_data[[paste0('tf_', col, '_l')]]
    tf_r <- tf_data[[paste0('tf_', col, '_r')]]

    if (!is.null(tf_l) && !is.null(tf_r)) {
      tf_max <- pmax(tf_l, tf_r, na.rm = TRUE)
      max_level <- n_gamma_levels(comp$method) - 1L
      u_exact <- mu$u_levels[[col]][max_level + 1L]
      mask <- gamma_mat[, j] == max_level & !is.na(tf_max) & tf_max > 0
      if (any(mask)) {
        adj[mask] <- log2(pmax(u_exact, 1e-10) / tf_max[mask])
      }
    }

    adj_list[[col]] <- adj
  }

  adj_list
}

#' R-side TF lookup for the SQLite fallback path
#'
#' Reads pre-computed TF tables from the database and joins them to the
#' pairs data frame in R.
#'
#' @param model An il_model object.
#' @param pairs Data frame of pairs (with `l_<col>` and `r_<col>` columns).
#' @param tf_cols Character vector of column names with TF enabled.
#' @return A data frame with `tf_<col>_l` and `tf_<col>_r` columns.
#' @noRd
lookup_tf_r <- function(model, pairs, tf_cols) {
  con <- model$con
  tf_data <- data.frame(row.names = seq_len(nrow(pairs)))

  for (col in tf_cols) {
    tf_tbl <- paste0('__il_tf_', col)
    tf_df <- DBI::dbReadTable(con, tf_tbl)
    tf_col_name <- paste0('tf_', col)

    # Left values
    l_vals <- pairs[[paste0('l_', col)]]
    tf_data[[paste0('tf_', col, '_l')]] <-
      tf_df[[tf_col_name]][match(l_vals, tf_df[[col]])]

    # Right values
    r_vals <- pairs[[paste0('r_', col)]]
    tf_data[[paste0('tf_', col, '_r')]] <-
      tf_df[[tf_col_name]][match(r_vals, tf_df[[col]])]
  }

  tf_data
}
