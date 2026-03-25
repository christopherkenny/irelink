#' Compute Precision-Recall Curve Data
#'
#' Returns a tidy tibble of precision and recall values at each
#' match-probability threshold. Requires labelled pairs. Designed for use
#' with [ggplot2::geom_line()].
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator.
#'
#' @return A tibble with columns `threshold`, `precision`, and `recall`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_precision_recall(model, labels = labelled_pairs) |>
#'   ggplot2::ggplot(ggplot2::aes(x = recall, y = precision)) +
#'   ggplot2::geom_line()
#' }
il_precision_recall <- function(model, labels) {
  cli::cli_warn("Function {.fn il_precision_recall} is not yet implemented.")
  invisible(NULL)
}
