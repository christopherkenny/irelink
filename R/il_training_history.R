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
  validate_il_model(model)
  history <- model$params$history
  if (is.null(history) || length(history) == 0L) {
    cli::cli_abort("No training history available. Run {.fn il_estimate_em} first.")
  }
  do.call(rbind, history)
}
