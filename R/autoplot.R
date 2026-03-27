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
#' @exportS3Method ggplot2::autoplot
autoplot.il_model <- function(object, ...) {
  if (!requireNamespace('ggplot2', quietly = TRUE)) {
    cli::cli_abort('Package {.pkg ggplot2} is required for autoplot.')
  }
  wt <- il_weights(object)
  ggplot2::ggplot(wt, ggplot2::aes(
    x = .data[['comparison']], y = .data[['weight']], fill = .data[['level']]
  )) +
    ggplot2::geom_col(position = 'dodge') +
    ggplot2::labs(
      title = 'Match Weights', x = 'Comparison', y = 'Weight (log2)',
      fill = 'Level'
    ) +
    ggplot2::theme_minimal()
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
#' @exportS3Method ggplot2::autoplot
autoplot.il_compared <- function(object, which = NULL, ...) {
  if (!requireNamespace('ggplot2', quietly = TRUE)) {
    cli::cli_abort('Package {.pkg ggplot2} is required for autoplot.')
  }
  if (!is.null(which)) {
    wf <- il_waterfall(object, which = which)
    return(
      ggplot2::ggplot(wf, ggplot2::aes(
        x = stats::reorder(.data[['step']], seq_len(nrow(wf))),
        y = .data[['contribution']]
      )) +
        ggplot2::geom_col() +
        ggplot2::coord_flip() +
        ggplot2::labs(title = 'Waterfall', x = 'Comparison', y = 'Contribution') +
        ggplot2::theme_minimal()
    )
  }
  ggplot2::ggplot(object, ggplot2::aes(x = .data[['match_weight']])) +
    ggplot2::geom_histogram(binwidth = 1, fill = 'steelblue') +
    ggplot2::labs(
      title = 'Match Weight Distribution',
      x = 'Match Weight (log2)', y = 'Count'
    ) +
    ggplot2::theme_minimal()
}
