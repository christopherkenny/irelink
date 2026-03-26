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
#' Predicts all pairs (threshold = 0), then looks up each labeled pair's
#' match probability and match weight.
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
  all_pairs <- predict(model, threshold = 0.0)

  pred_keys <- canonical_pair_key(all_pairs$unique_id_l, all_pairs$unique_id_r)
  pred_probs <- setNames(all_pairs$match_probability, pred_keys)
  pred_weights <- setNames(all_pairs$match_weight, pred_keys)

  label_keys <- canonical_pair_key(labels$unique_id_l, labels$unique_id_r)

  label_probs <- vapply(label_keys, function(k) {
    if (k %in% names(pred_probs)) pred_probs[[k]] else 0.0
  }, numeric(1), USE.NAMES = FALSE)

  label_weights <- vapply(label_keys, function(k) {
    if (k %in% names(pred_weights)) pred_weights[[k]] else NA_real_
  }, numeric(1), USE.NAMES = FALSE)

  list(
    label_probs = label_probs,
    label_weights = label_weights,
    actual_positive = as.logical(labels$is_match)
  )
}
