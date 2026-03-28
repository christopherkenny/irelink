# Shared helpers for evaluation functions (il_accuracy, il_errors, etc.).

#' Build canonical pair keys for direction-independent matching
#'
#' Ensures pair (A, B) and pair (B, A) produce the same key by placing the
#' lexicographically smaller ID first.
#'
#' @param id_l Character or integer vector of left IDs.
#' @param id_r Character or integer vector of right IDs.
#' @return Character vector of canonical pair keys.
#' @noRd
canonical_pair_key <- function(id_l, id_r) {
  l <- as.character(id_l)
  r <- as.character(id_r)
  paste(pmin(l, r), pmax(l, r), sep = '||')
}

#' Score labeled pairs against model predictions
#'
#' Scores only the labeled pairs directly instead of predicting all pairs.
#' Builds pair rows from the model's data and scores them in one batch.
#'
#' @param model A trained `il_model`.
#' @param labels A data frame with `unique_id_l`, `unique_id_r`, `is_match`.
#' @return A list with elements:
#'   - `label_probs`: numeric vector of match probabilities per labeled pair
#'   - `label_weights`: numeric vector of match weights per labeled pair
#'   - `actual_positive`: logical vector of true match status
#' @noRd
score_labeled_pairs <- function(model, labels) {
  validate_il_model(model)

  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- model$params$prior %||% 0.05
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  mu <- extract_mu_vectors(params, comp_names)

  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  id_l <- as.character(labels$unique_id_l)
  id_r <- as.character(labels$unique_id_r)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: upload labels to temp table, JOIN to data, compute gammas
    lbl_tbl <- '__il_eval_labels'
    lbl_df <- data.frame(
      pair_idx = seq_len(nrow(labels)),
      uid_l = id_l,
      uid_r = id_r,
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(con, lbl_tbl, as.data.frame(lbl_df), overwrite = TRUE)
    on.exit(drop_registered(con, lbl_tbl), add = TRUE)

    gamma_exprs <- vapply(comparisons, function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue('{expr} AS gamma_{comp$columns}')
    }, character(1))
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    sql <- glue::glue(
      'SELECT lbl.pair_idx, {gamma_select} ',
      'FROM {lbl_tbl} lbl ',
      'JOIN {tbl_l} l ON l.unique_id = lbl.uid_l ',
      'JOIN {tbl_r} r ON r.unique_id = lbl.uid_r ',
      'ORDER BY lbl.pair_idx'
    )
    result <- DBI::dbGetQuery(con, sql)

    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names
  } else {
    # Fallback: read only the needed rows via SQL WHERE clause
    all_ids <- unique(c(id_l, id_r))
    id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

    cols_needed <- unique(c('unique_id', comp_names))
    col_select <- paste(cols_needed, collapse = ', ')

    sql_l <- glue::glue(
      'SELECT {col_select} FROM {tbl_l} WHERE unique_id IN ({id_list})'
    )
    src_l <- DBI::dbGetQuery(con, sql_l)
    rownames(src_l) <- as.character(src_l$unique_id)

    if (tbl_r == tbl_l) {
      src_r <- src_l
    } else {
      sql_r <- glue::glue(
        'SELECT {col_select} FROM {tbl_r} WHERE unique_id IN ({id_list})'
      )
      src_r <- DBI::dbGetQuery(con, sql_r)
      rownames(src_r) <- as.character(src_r$unique_id)
    }

    n_labels <- nrow(labels)
    pairs <- data.frame(row.names = seq_len(n_labels))
    for (col in comp_names) {
      pairs[[paste0('l_', col)]] <- src_l[id_l, col]
      pairs[[paste0('r_', col)]] <- src_r[id_r, col]
    }

    gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  }

  label_weights <- score_gamma_matrix(gamma_mat, mu)
  label_probs <- weight_to_probability(label_weights, prior)

  list(
    label_probs = label_probs,
    label_weights = label_weights,
    actual_positive = as.logical(labels$is_match)
  )
}
