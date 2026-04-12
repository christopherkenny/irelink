# Shared helpers for evaluation functions (il_accuracy, il_errors, etc.).

#' Derive Pairwise Labels from a Ground-Truth Column
#'
#' Given a model and a column name containing cluster or entity IDs,
#' generates pairwise labels for all predicted pairs. Two records
#' sharing the same value in `labels_col` are labelled as matches.
#'
#' This is a convenience wrapper: instead of manually building a labels
#' data frame with `unique_id_l`, `unique_id_r`, and `is_match`, you
#' supply the column name and let irelink derive everything.
#'
#' @param model A trained `il_model` object.
#' @param labels_col A string naming the column in the original data that
#'   contains the ground-truth cluster or entity identifier.
#' @param threshold Match-probability threshold for selecting predicted
#'   pairs. Defaults to `0` to include all candidate pairs.
#'
#' @return A data frame with columns `unique_id_l`, `unique_id_r`, and
#'   `is_match` (integer 0/1).
#' @export
#'
#' @examples
#' \donttest{
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
#' model <- il_model(fake_1000, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' labels_from_column(model, 'cluster')
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' }
labels_from_column <- function(model, labels_col, threshold = 0) {
  validate_il_model(model)
  con <- model$con
  dialect <- detect_dialect(con)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: predict lazily, resolve labels via SQL JOIN, collect only the
    # small labels frame — never materialise the full pair set into R.
    lazy <- predict_lazy(model, threshold)
    on.exit(drop_registered(con, lazy$predicted_tbl), add = TRUE)
    tbl_l <- model$data$tbl_l
    tbl_r <- model$data$tbl_r %||% tbl_l
    sql <- glue::glue(
      'SELECT p.unique_id_l, p.unique_id_r, ',
      'CASE WHEN gl.{labels_col} IS NOT NULL ',
      'AND gr.{labels_col} IS NOT NULL ',
      'AND gl.{labels_col} = gr.{labels_col} THEN 1 ELSE 0 END AS is_match ',
      'FROM {lazy$predicted_tbl} p ',
      'JOIN {tbl_l} gl ON gl.unique_id = p.unique_id_l ',
      'JOIN {tbl_r} gr ON gr.unique_id = p.unique_id_r'
    )
    return(DBI::dbGetQuery(con, sql))
  }

  # Fallback: collect + R-side label resolution
  pairs <- predict(model, threshold = threshold)
  resolve_labels_from_pairs(model, pairs, labels_col)
}

#' Resolve labels for already-predicted pairs
#' @noRd
resolve_labels_from_pairs <- function(model, pairs, labels_col) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  id_l <- as.character(pairs$unique_id_l)
  id_r <- as.character(pairs$unique_id_r)
  all_ids <- unique(c(id_l, id_r))
  id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

  # Fetch ground-truth column for all relevant IDs
  sql_l <- glue::glue(
    'SELECT unique_id, {labels_col} FROM {tbl_l} WHERE unique_id IN ({id_list})'
  )
  gt_l <- DBI::dbGetQuery(con, sql_l)
  rownames(gt_l) <- as.character(gt_l$unique_id)

  if (tbl_r == tbl_l) {
    gt_r <- gt_l
  } else {
    sql_r <- glue::glue(
      'SELECT unique_id, {labels_col} FROM {tbl_r} WHERE unique_id IN ({id_list})'
    )
    gt_r <- DBI::dbGetQuery(con, sql_r)
    rownames(gt_r) <- as.character(gt_r$unique_id)
  }

  val_l <- gt_l[id_l, labels_col]
  val_r <- gt_r[id_r, labels_col]
  is_match <- as.integer(!is.na(val_l) & !is.na(val_r) & val_l == val_r)

  data.frame(
    unique_id_l = pairs$unique_id_l,
    unique_id_r = pairs$unique_id_r,
    is_match = is_match,
    stringsAsFactors = FALSE
  )
}

#' Resolve labels argument: use labels directly or derive from labels_col
#' @noRd
resolve_labels <- function(model, labels, labels_col) {
  if (!is.null(labels_col)) {
    if (!is.null(labels)) {
      cli::cli_warn('Both {.arg labels} and {.arg labels_col} provided; using {.arg labels_col}.')
    }
    return(labels_from_column(model, labels_col))
  }
  if (is.null(labels)) {
    cli::cli_abort('Either {.arg labels} or {.arg labels_col} must be provided.')
  }
  labels
}

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
  prior <- safe_prior(model)
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  mu <- extract_mu_vectors(params, comp_names)

  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  id_l <- as.character(labels$unique_id_l)
  id_r <- as.character(labels$unique_id_r)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: upload labels, JOIN to data, compute gammas AND score in SQL
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

    # Build weight expression using model parameters
    weight_parts <- vapply(seq_along(comparisons), function(j) {
      cn <- comp_names[j]
      sql_weight_case(cn, mu$m_levels[[cn]], mu$u_levels[[cn]])
    }, character(1))
    weight_expr <- paste(weight_parts, collapse = ' + ')
    log_prior_odds <- log(prior / (1 - prior))
    ln2 <- log(2)

    sql <- glue::glue(
      'SELECT pair_idx, match_weight, ',
      '1.0 / (1.0 + EXP(-({log_prior_odds} + match_weight * {ln2}))) ',
      'AS match_probability ',
      'FROM (',
      'SELECT pair_idx, ({weight_expr}) AS match_weight ',
      'FROM (',
      'SELECT lbl.pair_idx, {gamma_select} ',
      'FROM {lbl_tbl} lbl ',
      'JOIN {tbl_l} l ON l.unique_id = lbl.uid_l ',
      'JOIN {tbl_r} r ON r.unique_id = lbl.uid_r',
      ') AS gamma_pairs',
      ') AS weighted_pairs ORDER BY pair_idx'
    )
    result <- DBI::dbGetQuery(con, sql)

    return(list(
      label_probs = result$match_probability,
      label_weights = result$match_weight,
      actual_positive = as.logical(labels$is_match)
    ))
  }

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
  label_weights <- score_gamma_matrix(gamma_mat, mu)
  label_probs <- weight_to_probability(label_weights, prior)

  list(
    label_probs = label_probs,
    label_weights = label_weights,
    actual_positive = as.logical(labels$is_match)
  )
}
