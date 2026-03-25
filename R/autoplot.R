#' Quick Match-Weights Plot for a Model
#'
#' Produces a ready-made match-weights chart from a trained model. This
#' is a convenience wrapper; for full control, extract data with
#' [il_weights()] and build a custom [ggplot2::ggplot()].
#'
#' @param object A trained `il_model` object.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @export
#'
#' @examples
#' \dontrun{
#' autoplot(model)
#' }
autoplot.il_model <- function(object, ...) {
  cli::cli_warn("Function {.fn autoplot.il_model} is not yet implemented.")
  invisible(NULL)
}

#' Quick Plot for Scored Pairs
#'
#' Produces a match-weight histogram from scored pairs, or a waterfall
#' chart for a single pair when `which` is provided. This is a
#' convenience wrapper; for full control, use [ggplot2::ggplot()]
#' directly on the tibble or on data from [il_waterfall()].
#'
#' @param object An `il_compared` tibble from [predict.il_model()].
#' @param which An optional integer index. If provided, produces a
#'   waterfall chart for that pair. If `NULL` (default), produces a
#'   histogram.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @export
#'
#' @examples
#' \dontrun{
#' # Match-weight histogram
#' autoplot(pairs)
#'
#' # Waterfall for the first pair
#' autoplot(pairs, which = 1)
#' }
autoplot.il_compared <- function(object, which = NULL, ...) {
  cli::cli_warn("Function {.fn autoplot.il_compared} is not yet implemented.")
  invisible(NULL)
}
