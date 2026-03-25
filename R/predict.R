#' Score Record Pairs from a Trained Model
#'
#' Generates and scores all candidate record pairs that pass the blocking
#' rules, returning those above the match-probability threshold. This is
#' an S3 method for [stats::predict()] — the same generic used for `lm`,
#' `glm`, and tidymodels objects.
#'
#' @param object A trained `il_model` object.
#' @param threshold A numeric value between 0 and 1. Only pairs with a
#'   match probability at or above this threshold are returned. Defaults
#'   to `0.85`.
#' @param type One of `"pairs"` (default) to return scored pairs, or
#'   `"weights"` to return match weights on a log-2 Bayes-factor scale.
#' @param ... Additional arguments passed to the generic.
#'
#' @return An `il_compared` tibble with one row per candidate pair,
#'   including columns for record IDs, match weight, match probability,
#'   and per-comparison gamma values.
#' @export
#'
#' @examples
#' \dontrun{
#' pairs <- predict(model, threshold = 0.85)
#'
#' # Filter to high-confidence matches
#' pairs |> dplyr::filter(match_prob > 0.99)
#'
#' # Histogram of match weights
#' pairs |>
#'   ggplot2::ggplot(ggplot2::aes(x = match_weight)) +
#'   ggplot2::geom_histogram(binwidth = 1, fill = "steelblue")
#' }
predict.il_model <- function(object, threshold = 0.85,
                             type = c("pairs", "weights"), ...) {
  cli::cli_warn("Function {.fn predict.il_model} is not yet implemented.")
  invisible(NULL)
}
