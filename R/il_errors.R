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
  cli::cli_warn("Function {.fn il_errors} is not yet implemented.")
  invisible(NULL)
}
