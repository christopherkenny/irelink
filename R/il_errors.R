#' Identify Prediction Errors
#'
#' Compares model predictions against labelled pairs and returns all
#' false-positive and false-negative errors at a given threshold. Useful
#' for understanding which record pairs the model gets wrong.
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator.
#' @param threshold A numeric value between 0 and 1 for classifying pairs
#'   as matches. Defaults to `0.85`.
#'
#' @return A tibble of misclassified pairs with columns `id_l`, `id_r`,
#'   `match_weight`, `match_prob`, `true_label`, and `error_type`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_errors(model, labels = labelled_pairs, threshold = 0.85)
#' }
il_errors <- function(model, labels, threshold = 0.85) {
  validate_il_model(model)
  all_pairs <- predict(model, threshold = 0.0)

  pair_key_fn <- function(l, r) {
    l <- as.character(l)
    r <- as.character(r)
    paste(pmin(l, r), pmax(l, r), sep = "||")
  }

  pred_keys <- pair_key_fn(all_pairs$unique_id_l, all_pairs$unique_id_r)
  pred_probs <- setNames(all_pairs$match_probability, pred_keys)
  pred_weights <- setNames(all_pairs$match_weight, pred_keys)

  label_keys <- pair_key_fn(labels$unique_id_l, labels$unique_id_r)
  label_probs <- vapply(label_keys, function(k) {
    if (k %in% names(pred_probs)) pred_probs[[k]] else 0.0
  }, numeric(1), USE.NAMES = FALSE)
  label_weights <- vapply(label_keys, function(k) {
    if (k %in% names(pred_weights)) pred_weights[[k]] else NA_real_
  }, numeric(1), USE.NAMES = FALSE)

  predicted_positive <- label_probs >= threshold
  actual_positive <- as.logical(labels$is_match)

  is_fp <- predicted_positive & !actual_positive
  is_fn <- !predicted_positive & actual_positive
  errors <- is_fp | is_fn

  tibble::tibble(
    unique_id_l = labels$unique_id_l[errors],
    unique_id_r = labels$unique_id_r[errors],
    match_weight = label_weights[errors],
    match_probability = label_probs[errors],
    true_label = actual_positive[errors],
    error_type = ifelse(is_fp[errors], "false_positive", "false_negative")
  )
}
