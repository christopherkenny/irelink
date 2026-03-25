#' Extract Match Weights by Comparison Level
#'
#' Returns a tidy tibble of comparison levels with their m probabilities,
#' u probabilities, and log-2 Bayes factors (match weights). Designed for
#' use with [ggplot2::geom_col()] and [ggplot2::facet_wrap()].
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `comparison`, `level`, `m_prob`,
#'   `u_prob`, and `log2_bayes_factor`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_weights(model) |>
#'   ggplot2::ggplot(ggplot2::aes(x = level, y = log2_bayes_factor)) +
#'   ggplot2::geom_col() +
#'   ggplot2::facet_wrap(~ comparison, scales = "free_x") +
#'   ggplot2::coord_flip()
#' }
il_weights <- function(model) {
  cli::cli_warn("Function {.fn il_weights} is not yet implemented.")
  invisible(NULL)
}
