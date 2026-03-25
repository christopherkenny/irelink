#' Extract Model Parameters
#'
#' Returns a tidy tibble of m and u probabilities for every comparison
#' level in the model. Designed for use with [ggplot2::geom_point()].
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `comparison`, `level`, `m_prob`, and
#'   `u_prob`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_parameters(model) |>
#'   ggplot2::ggplot(ggplot2::aes(x = u_prob, y = m_prob, color = comparison)) +
#'   ggplot2::geom_point(size = 3)
#' }
il_parameters <- function(model) {
  cli::cli_warn("Function {.fn il_parameters} is not yet implemented.")
  invisible(NULL)
}
