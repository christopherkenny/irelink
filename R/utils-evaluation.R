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
  paste(pmin(l, r), pmax(l, r), sep = "||")
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
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  # Read the source data and index by unique_id
  src_l <- DBI::dbReadTable(con, tbl_l)
  rownames(src_l) <- as.character(src_l$unique_id)
  if (tbl_r == tbl_l) {
    src_r <- src_l
  } else {
    src_r <- DBI::dbReadTable(con, tbl_r)
    rownames(src_r) <- as.character(src_r$unique_id)
  }

  id_l <- as.character(labels$unique_id_l)
  id_r <- as.character(labels$unique_id_r)

  # Build pair data frame for the labeled subset only
  n_labels <- nrow(labels)
  pairs <- data.frame(row.names = seq_len(n_labels))
  for (col in comp_names) {
    pairs[[paste0("l_", col)]] <- src_l[id_l, col]
    pairs[[paste0("r_", col)]] <- src_r[id_r, col]
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
