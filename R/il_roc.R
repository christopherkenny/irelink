#' Compute ROC Curve Data
#'
#' Returns a tidy tibble of false-positive rates and true-positive rates
#' at each match-probability threshold, for plotting an ROC curve.
#' Requires labelled pairs. Designed for use with [ggplot2::geom_line()].
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator.
#'
#' @return A tibble with columns `threshold`, `fpr`, and `tpr`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_roc(model, labels = labelled_pairs) |>
#'   ggplot2::ggplot(ggplot2::aes(x = fpr, y = tpr)) +
#'   ggplot2::geom_line() +
#'   ggplot2::geom_abline(linetype = "dashed") +
#'   ggplot2::coord_equal()
#' }
il_roc <- function(model, labels) {
  acc <- il_accuracy(model, labels)
  tibble::tibble(
    threshold = acc$threshold,
    fpr = acc$fp / pmax(acc$fp + acc$tn, 1L),
    tpr = acc$tp / pmax(acc$tp + acc$fn, 1L)
  )
}
