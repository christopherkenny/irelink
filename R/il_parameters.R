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
  validate_il_model(model)
  params <- model$params$comparisons
  if (is.null(params)) {
    cli::cli_abort("Model has no parameters yet. Run training verbs first.")
  }
  params
}
