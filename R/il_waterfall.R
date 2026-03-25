#' Extract Waterfall Data for a Single Pair
#'
#' Returns a tidy tibble showing how each comparison contributed to the
#' total match weight for a specific record pair. Designed for use with
#' [ggplot2::geom_col()] and [ggplot2::coord_flip()].
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param which An integer index identifying which row (pair) to
#'   decompose. Defaults to `1L`.
#'
#' @return A tibble with columns `step`, `order`, `contribution`, and
#'   `direction` (positive, negative, prior, or final).
#' @export
#'
#' @examples
#' \dontrun{
#' il_waterfall(pairs, which = 1) |>
#'   ggplot2::ggplot(ggplot2::aes(
#'     x = reorder(step, order), y = contribution, fill = direction
#'   )) +
#'   ggplot2::geom_col() +
#'   ggplot2::coord_flip()
#' }
il_waterfall <- function(pairs, which = 1L) {
  cli::cli_warn("Function {.fn il_waterfall} is not yet implemented.")
  invisible(NULL)
}
