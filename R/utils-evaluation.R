# Shared helpers for evaluation functions (il_accuracy, il_errors, etc.).

#' Derive Pairwise Labels from a Ground-Truth Column
#'
#' Given a model and a column name containing cluster or entity IDs,
#' generates pairwise labels for all predicted pairs. Two records
#' sharing the same value in `labels_col` are labeled as matches.
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
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
#' model <- il_model(fake_1000, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' labels_from_column(model, 'cluster')
#' DBI::dbDisconnect(con, shutdown = TRUE)
labels_from_column <- function(model, labels_col, threshold = 0) {
  validate_il_model(model)
  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l
  qtbl_l <- sql_quote_identifier(tbl_l)
  qtbl_r <- sql_quote_identifier(tbl_r)
  qlabels_col <- sql_quote_identifier(labels_col)
  link_type <- model$link_type %||% 'dedupe'
  dedup_cond <- if (link_type == 'dedupe') {
    'AND gl.unique_id < gr.unique_id '
  } else {
    ''
  }

  if (dialect_has_fuzzy_sql(dialect)) {
    lazy <- predict_lazy(model, threshold)
    on.exit(drop_registered(con, lazy$predicted_tbl), add = TRUE)
    # Universe = all true match pairs (from data) UNION all candidate pairs.
    # This ensures true matches missed by blocking are counted as FNs.
    sql <- glue::glue(
      'WITH true_matches AS (',
      'SELECT gl.unique_id AS unique_id_l, gr.unique_id AS unique_id_r ',
      'FROM {qtbl_l} gl JOIN {qtbl_r} gr ',
      'ON gl.{qlabels_col} IS NOT NULL AND gr.{qlabels_col} IS NOT NULL ',
      'AND gl.{qlabels_col} = gr.{qlabels_col} {dedup_cond}',
      '), universe AS (',
      'SELECT unique_id_l, unique_id_r FROM true_matches ',
      'UNION ',
      'SELECT unique_id_l, unique_id_r FROM {sql_quote_identifier(lazy$predicted_tbl)}',
      ') ',
      'SELECT u.unique_id_l, u.unique_id_r, ',
      'CASE WHEN tm.unique_id_l IS NOT NULL THEN 1 ELSE 0 END AS is_match ',
      'FROM universe u ',
      'LEFT JOIN true_matches tm ',
      'ON tm.unique_id_l = u.unique_id_l AND tm.unique_id_r = u.unique_id_r'
    )
    return(DBI::dbGetQuery(con, sql))
  }

  # Fallback: collect all true matches from data + candidate pairs, label both
  sql_true <- glue::glue(
    'SELECT gl.unique_id AS unique_id_l, gr.unique_id AS unique_id_r ',
    'FROM {qtbl_l} gl JOIN {qtbl_r} gr ',
    'ON gl.{qlabels_col} IS NOT NULL AND gr.{qlabels_col} IS NOT NULL ',
    'AND gl.{qlabels_col} = gr.{qlabels_col} {dedup_cond}'
  )
  true_pairs <- DBI::dbGetQuery(con, sql_true)
  true_pairs$is_match <- 1L
  candidates <- predict(model, threshold = threshold)
  cand_labeled <- resolve_labels_from_pairs(model, candidates, labels_col)
  combined <- rbind(true_pairs, cand_labeled)
  key <- canonical_pair_key(combined$unique_id_l, combined$unique_id_r)
  combined[!duplicated(key), ]
}

#' Resolve labels for already-predicted pairs
#' @noRd
resolve_labels_from_pairs <- function(model, pairs, labels_col) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l
  qtbl_l <- sql_quote_identifier(tbl_l)
  qtbl_r <- sql_quote_identifier(tbl_r)
  qlabels_col <- sql_quote_identifier(labels_col)

  id_l <- as.character(pairs$unique_id_l)
  id_r <- as.character(pairs$unique_id_r)
  all_ids <- unique(c(id_l, id_r))
  id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

  # Fetch ground-truth column for all relevant IDs
  sql_l <- glue::glue(
    'SELECT unique_id, {qlabels_col} FROM {qtbl_l} WHERE unique_id IN ({id_list})'
  )
  gt_l <- DBI::dbGetQuery(con, sql_l)
  rownames(gt_l) <- as.character(gt_l$unique_id)

  if (tbl_r == tbl_l) {
    gt_r <- gt_l
  } else {
    sql_r <- glue::glue(
      'SELECT unique_id, {qlabels_col} FROM {qtbl_r} WHERE unique_id IN ({id_list})'
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
      cli::cli_warn(
        'Both {.arg labels} and {.arg labels_col} provided; using {.arg labels_col}.'
      )
    }
    return(labels_from_column(model, labels_col))
  }
  if (is.null(labels)) {
    cli::cli_abort(
      'Either {.arg labels} or {.arg labels_col} must be provided.'
    )
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
#'   - `found_by_blocking`: logical vector indicating whether blocking would
#'     find this pair
#' @noRd
score_labeled_pairs <- function(model, labels) {
  validate_il_model(model)

  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- safe_prior(model)
  comp_names <- comparison_names(comparisons)
  mu <- extract_mu_vectors(params, comp_names)

  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l
  qtbl_l <- sql_quote_identifier(tbl_l)
  qtbl_r <- sql_quote_identifier(tbl_r)

  id_l <- as.character(labels$unique_id_l)
  id_r <- as.character(labels$unique_id_r)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: upload labels, JOIN to data, compute gammas AND score in SQL
    lbl_tbl <- il_table_name(model, 'eval_labels', il_table_suffix())
    lbl_df <- data.frame(
      pair_idx = seq_len(nrow(labels)),
      uid_l = id_l,
      uid_r = id_r,
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(con, lbl_tbl, as.data.frame(lbl_df), overwrite = TRUE)
    on.exit(drop_registered(con, lbl_tbl), add = TRUE)

    gamma_exprs <- vapply(
      comparisons,
      function(comp) {
        expr <- sql_gamma_case(comp, dialect)
        glue::glue(
          '{expr} AS {sql_quote_identifier(paste0("gamma_", comparison_name(comp)))}'
        )
      },
      character(1)
    )
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    # Blocking-miss flag: evaluate whether each pair matches any blocking rule
    blocking_rules <- model$spec$blocking_rules
    if (length(blocking_rules) > 0L) {
      br_exprs <- vapply(
        blocking_rules,
        function(br) {
          build_blocking_condition(
            br$columns,
            br$where,
            transform = br$transform,
            dialect = dialect
          )
        },
        character(1)
      )
      br_sql <- paste0('(', paste(br_exprs, collapse = ' OR '), ')')
    } else {
      br_sql <- 'TRUE'
    }

    # Build weight expression using model parameters
    weight_parts <- vapply(
      seq_along(comparisons),
      function(j) {
        cn <- comp_names[j]
        sql_weight_case(cn, mu$m_levels[[cn]], mu$u_levels[[cn]])
      },
      character(1)
    )
    weight_expr <- paste(weight_parts, collapse = ' + ')
    log_prior_odds <- log(prior / (1 - prior))
    ln2 <- log(2)

    sql <- glue::glue(
      'SELECT pair_idx, match_weight, ',
      '1.0 / (1.0 + EXP(-({log_prior_odds} + match_weight * {ln2}))) ',
      'AS match_probability, found_by_blocking ',
      'FROM (',
      'SELECT pair_idx, ({weight_expr}) AS match_weight, ',
      'found_by_blocking ',
      'FROM (',
      'SELECT lbl.pair_idx, {gamma_select}, ',
      '{br_sql} AS found_by_blocking ',
      'FROM {sql_quote_identifier(lbl_tbl)} lbl ',
      'JOIN {qtbl_l} l ON l.unique_id = lbl.uid_l ',
      'JOIN {qtbl_r} r ON r.unique_id = lbl.uid_r',
      ') AS gamma_pairs',
      ') AS weighted_pairs ORDER BY pair_idx'
    )
    result <- DBI::dbGetQuery(con, sql)

    return(list(
      label_probs = result$match_probability,
      label_weights = result$match_weight,
      actual_positive = as.logical(labels$is_match),
      found_by_blocking = as.logical(unlist(result$found_by_blocking))
    ))
  }

  # Fallback: read only the needed rows via SQL WHERE clause
  all_ids <- unique(c(id_l, id_r))
  id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

  cols_needed <- unique(c('unique_id', comp_names))
  col_select <- sql_identifier_csv(cols_needed)
  qtbl_l <- sql_quote_identifier(tbl_l)
  qtbl_r <- sql_quote_identifier(tbl_r)

  sql_l <- glue::glue(
    'SELECT {col_select} FROM {qtbl_l} WHERE unique_id IN ({id_list})'
  )
  src_l <- DBI::dbGetQuery(con, sql_l)
  rownames(src_l) <- as.character(src_l$unique_id)

  if (tbl_r == tbl_l) {
    src_r <- src_l
  } else {
    sql_r <- glue::glue(
      'SELECT {col_select} FROM {qtbl_r} WHERE unique_id IN ({id_list})'
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

  # Blocking-miss flag (R path): check each pair against blocking rules
  blocking_rules <- model$spec$blocking_rules
  if (length(blocking_rules) > 0L) {
    found <- logical(n_labels)
    for (br in blocking_rules) {
      rule_match <- rep(TRUE, n_labels)
      for (col in br$columns) {
        l_vals <- src_l[id_l, col]
        r_vals <- src_r[id_r, col]
        rule_match <- rule_match &
          !is.na(l_vals) &
          !is.na(r_vals) &
          l_vals == r_vals
      }
      found <- found | rule_match
    }
  } else {
    found <- rep(TRUE, n_labels)
  }

  list(
    label_probs = label_probs,
    label_weights = label_weights,
    actual_positive = as.logical(labels$is_match),
    found_by_blocking = found
  )
}

#' Compute thresholded confusion-matrix counts from scored labels
#'
#' Shared by evaluation helpers such as [il_accuracy()] and
#' [il_confusion_matrix()].
#'
#' @param label_probs Numeric vector of match probabilities.
#' @param actual_positive Logical vector of ground-truth match status.
#' @param found_by_blocking Optional logical vector indicating whether the
#'   pair would have been generated by the model's blocking rules.
#' @param threshold Numeric threshold for classifying pairs as matches.
#' @return A one-row tibble with `tp`, `fp`, `fn`, `tn`, and
#'   `fn_blocking_miss`.
#' @noRd
compute_confusion_counts <- function(label_probs, actual_positive,
                                     found_by_blocking = NULL,
                                     threshold = 0.85) {
  predicted_positive <- label_probs >= threshold

  if (!is.null(found_by_blocking)) {
    found_by_blocking <- !is.na(found_by_blocking) & found_by_blocking
    predicted_positive <- predicted_positive & found_by_blocking
  }

  tp <- sum(predicted_positive & actual_positive)
  fp <- sum(predicted_positive & !actual_positive)
  fn <- sum(!predicted_positive & actual_positive)
  tn <- sum(!predicted_positive & !actual_positive)

  if (is.null(found_by_blocking)) {
    fn_blocking_miss <- NA_integer_
  } else {
    fn_blocking_miss <- sum(actual_positive & !found_by_blocking)
  }

  tibble::tibble(
    tp = tp,
    fp = fp,
    fn = fn,
    tn = tn,
    fn_blocking_miss = fn_blocking_miss
  )
}

#' Add summary metrics to confusion-matrix counts
#'
#' @param counts One-row data frame/tibble with `tp`, `fp`, `fn`, `tn`.
#' @param threshold Optional numeric threshold to include in the result.
#' @return A one-row tibble with counts and derived metrics.
#' @noRd
summarise_confusion_counts <- function(counts, threshold = NULL) {
  tp <- counts$tp
  fp <- counts$fp
  fn <- counts$fn
  tn <- counts$tn

  precision <- if (tp + fp > 0) tp / (tp + fp) else 1
  recall <- if (tp + fn > 0) tp / (tp + fn) else 1
  f1 <- if (precision + recall > 0) {
    2 * precision * recall / (precision + recall)
  } else {
    0
  }

  result <- tibble::tibble(
    tp = tp,
    fp = fp,
    fn = fn,
    tn = tn,
    fn_blocking_miss = counts$fn_blocking_miss,
    precision = precision,
    recall = recall,
    f1 = f1
  )

  if (!is.null(threshold)) {
    result <- tibble::add_column(result, threshold = threshold, .before = 1)
  }

  result
}
