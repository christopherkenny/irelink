#' Accuracy Metrics Across Thresholds
#'
#' Computes precision, recall, F1, and counts of true positives, false
#' positives, and false negatives at a range of match-probability
#' thresholds. Requires labelled pairs.
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator.
#'
#' @return A tibble with one row per threshold, containing columns
#'   `threshold`, `precision`, `recall`, `f1`, `tp`, `fp`, and `fn`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_accuracy(model, labels = labelled_pairs)
#' }
il_accuracy <- function(model, labels) {
  cli::cli_warn("Function {.fn il_accuracy} is not yet implemented.")
  invisible(NULL)
}
