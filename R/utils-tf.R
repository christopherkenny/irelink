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
#' For each comparison with `term_frequency = TRUE`, creates a model-scoped
#' table containing `(<col>, tf_<col>)` where `tf_<col>` is the proportion of
#' non-NULL records with that value.
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
  qtbl_l <- sql_quote_identifier(tbl_l)
  qtbl_r <- NULL
  if (!is.null(tbl_r)) {
    qtbl_r <- sql_quote_identifier(tbl_r)
  }

  tf_tables <- list()
  for (col in tf_cols) {
    tf_tbl <- il_table_name(model, 'tf', col)
    qcol <- sql_quote_identifier(col)
    qtf_tbl <- sql_quote_identifier(tf_tbl)
    qtf_col <- sql_quote_identifier(paste0('tf_', col))

    if (!is.null(tbl_r)) {
      # Link mode: compute from union of both tables
      union_sql <- glue::glue(
        'SELECT {qcol} FROM {qtbl_l} WHERE {qcol} IS NOT NULL ',
        'UNION ALL ',
        'SELECT {qcol} FROM {qtbl_r} WHERE {qcol} IS NOT NULL'
      )
      select_sql <- glue::glue(
        'SELECT {qcol}, CAST(COUNT(*) AS DOUBLE) / ',
        '(SELECT COUNT(*) FROM ({union_sql}) sub) AS {qtf_col} ',
        'FROM ({union_sql}) combined ',
        'GROUP BY {qcol}'
      )
    } else {
      # Dedupe mode: single table
      select_sql <- glue::glue(
        'SELECT {qcol}, CAST(COUNT(*) AS DOUBLE) / ',
        '(SELECT COUNT({qcol}) FROM {qtbl_l} WHERE {qcol} IS NOT NULL) AS {qtf_col} ',
        'FROM {qtbl_l} ',
        'WHERE {qcol} IS NOT NULL ',
        'GROUP BY {qcol}'
      )
    }

    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {qtf_tbl}'))
    DBI::dbExecute(con, glue::glue('CREATE TABLE {qtf_tbl} AS {select_sql}'))
    tf_tables[[col]] <- tf_tbl
  }

  model$data$tf_tables <- tf_tables
  for (tbl in unname(tf_tables)) {
    model <- il_track_table(model, tbl, owner = 'model')
  }
  model
}

#' Generate SQL SELECT expressions for term frequency columns
#'
#' Produces scalar subqueries that look up TF values for left and right
#' records from the pre-computed model-specific TF tables.
#'
#' @param tf_cols Character vector of column names with TF enabled.
#' @param tf_tables Named list mapping TF columns to table names.
#' @return A SQL fragment for the SELECT clause, or NULL if no TF columns.
#' @noRd
sql_tf_select_exprs <- function(tf_cols, tf_tables) {
  if (length(tf_cols) == 0L) {
    return(NULL)
  }
  if (is.null(tf_tables) || !all(tf_cols %in% names(tf_tables))) {
    missing <- setdiff(tf_cols, names(tf_tables %||% list()))
    cli::cli_abort(
      'Missing term-frequency table registration for column{?s} {.field {missing}}.'
    )
  }
  exprs <- character(0)
  for (col in tf_cols) {
    tf_tbl <- tf_tables[[col]]
    qtf_tbl <- sql_quote_identifier(tf_tbl)
    qcol <- sql_quote_identifier(col)
    qtf_col <- sql_quote_identifier(paste0('tf_', col))
    qtf_col_l <- sql_quote_identifier(paste0('tf_', col, '_l'))
    qtf_col_r <- sql_quote_identifier(paste0('tf_', col, '_r'))
    exprs <- c(
      exprs,
      glue::glue(
        '(SELECT {qtf_col} FROM {qtf_tbl} WHERE {qcol} = {sql_col_ref("l", col)}) AS {qtf_col_l}'
      ),
      glue::glue(
        '(SELECT {qtf_col} FROM {qtf_tbl} WHERE {qcol} = {sql_col_ref("r", col)}) AS {qtf_col_r}'
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

    if (!isTRUE(comp$method$term_frequency)) {
      next
    }

    tf_w <- comp$tf_adjustment_weight %||% 1.0
    if (tf_w == 0) {
      next
    }

    tf_l <- tf_data[[paste0('tf_', col, '_l')]]
    tf_r <- tf_data[[paste0('tf_', col, '_r')]]

    if (is.null(tf_l) || is.null(tf_r)) {
      next
    }

    # Use maximum of left/right TF values (following splink)
    tf_max <- pmax(tf_l, tf_r, na.rm = TRUE)

    # Apply tf_minimum_u_value floor
    tf_min <- comp$tf_minimum_u_value %||% 0.0
    if (tf_min > 0) {
      tf_max <- pmax(tf_max, tf_min)
    }

    # TF applies at the highest gamma level (exact match)
    max_level <- n_gamma_levels(comp$method) - 1L
    u_exact <- mu$u_levels[[col]][max_level + 1L]

    mask <- gamma_mat[, j] == max_level & !is.na(tf_max) & tf_max > 0
    if (any(mask)) {
      raw_adj <- log2(pmax(u_exact, 1e-10) / tf_max[mask])
      adjustment[mask] <- adjustment[mask] + tf_w * raw_adj
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

    if (!isTRUE(comp$method$term_frequency)) {
      next
    }

    tf_w <- comp$tf_adjustment_weight %||% 1.0
    if (tf_w == 0) {
      next
    }

    adj <- numeric(n_pairs)
    tf_l <- tf_data[[paste0('tf_', col, '_l')]]
    tf_r <- tf_data[[paste0('tf_', col, '_r')]]

    if (!is.null(tf_l) && !is.null(tf_r)) {
      tf_max <- pmax(tf_l, tf_r, na.rm = TRUE)
      tf_min <- comp$tf_minimum_u_value %||% 0.0
      if (tf_min > 0) {
        tf_max <- pmax(tf_max, tf_min)
      }
      max_level <- n_gamma_levels(comp$method) - 1L
      u_exact <- mu$u_levels[[col]][max_level + 1L]
      mask <- gamma_mat[, j] == max_level & !is.na(tf_max) & tf_max > 0
      if (any(mask)) {
        adj[mask] <- tf_w * log2(pmax(u_exact, 1e-10) / tf_max[mask])
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
    tf_tbl <- model$data$tf_tables[[col]]
    if (is.null(tf_tbl)) {
      cli::cli_abort(
        'Missing term-frequency table registration for column {.field {col}}.'
      )
    }
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
