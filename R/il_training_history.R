#' Extract EM Training History
#'
#' Returns a tidy tibble of parameter estimates at each EM iteration,
#' useful for diagnosing convergence. Designed for use with
#' [ggplot2::geom_line()] and [ggplot2::facet_wrap()].
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `iteration`, `comparison`, `level`, and
#'   `value`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_training_history(model) |>
#'   ggplot2::ggplot(ggplot2::aes(x = iteration, y = value, color = level)) +
#'   ggplot2::geom_line() +
#'   ggplot2::facet_wrap(~ comparison, scales = "free_y")
#' }
il_training_history <- function(model) {
  cli::cli_warn("Function {.fn il_training_history} is not yet implemented.")
  invisible(NULL)
}
