#' Compute Unlinkable Records
#'
#' Calculates the proportion of records that cannot be linked at each
#' match-probability threshold. Returns a tidy tibble for plotting the
#' "unlinkables curve" — useful for understanding how restrictive each
#' threshold is.
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `threshold` and `pct_unlinkable`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_unlinkables(model) |>
#'   ggplot2::ggplot(ggplot2::aes(x = threshold, y = pct_unlinkable)) +
#'   ggplot2::geom_line()
#' }
il_unlinkables <- function(model) {
  cli::cli_warn("Function {.fn il_unlinkables} is not yet implemented.")
  invisible(NULL)
}
