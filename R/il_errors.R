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
  scored <- score_labeled_pairs(model, labels)
  label_probs <- scored$label_probs
  label_weights <- scored$label_weights
  actual_positive <- scored$actual_positive

  predicted_positive <- label_probs >= threshold

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
