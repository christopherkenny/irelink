#' Quick Match-Weights Plot for a Model
#'
#' Produces a ready-made chart from a trained model. By default draws
#' the match-weights bar chart; set `type = "parameters"` for an m / u
#' probability comparison. For full control, extract data with
#' [il_weights()] or [il_parameters()] and build a custom
#' [ggplot2::ggplot()].
#'
#' @param object A trained `il_model` object.
#' @param type One of `"weights"` (default) or `"parameters"`.
#'   `"weights"` shows log-2 Bayes factors per comparison level.
#'   `"parameters"` shows m and u probabilities side by side.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_model <- function(object, type = c('weights', 'parameters'), ...) {
  rlang::check_installed('ggplot2')
  type <- match.arg(type)

  if (type == 'parameters') {
    wt <- il_weights(object)
    long <- rbind(
      tibble::tibble(
        comparison = wt$comparison, level = wt$level,
        probability = wt$m_prob, parameter = 'm'
      ),
      tibble::tibble(
        comparison = wt$comparison, level = wt$level,
        probability = wt$u_prob, parameter = 'u'
      )
    )
    return(
      ggplot2::ggplot(long, ggplot2::aes(
        x = .data[['comparison']], y = .data[['probability']],
        fill = .data[['parameter']]
      )) +
        ggplot2::geom_col(position = 'dodge') +
        ggplot2::facet_wrap(~ .data[['level']]) +
        ggplot2::labs(
          title = 'Model Parameters',
          x = 'Comparison', y = 'Probability', fill = 'Parameter'
        ) +
        ggplot2::theme_minimal()
    )
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
  rlang::check_installed('ggplot2')
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

#' Plot Accuracy Metrics Across Thresholds
#'
#' Draws precision, recall, and F1 against the match-probability
#' threshold. The data is produced by [il_accuracy()].
#'
#' @param object An `il_accuracy` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_accuracy <- function(object, ...) {
  rlang::check_installed('ggplot2')
  long <- rbind(
    tibble::tibble(
      threshold = object$threshold, value = object$precision,
      metric = 'Precision'
    ),
    tibble::tibble(
      threshold = object$threshold, value = object$recall,
      metric = 'Recall'
    ),
    tibble::tibble(
      threshold = object$threshold, value = object$f1,
      metric = 'F1'
    )
  )
  ggplot2::ggplot(long, ggplot2::aes(
    x = .data[['threshold']], y = .data[['value']],
    colour = .data[['metric']]
  )) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::labs(
      title = 'Accuracy Metrics by Threshold',
      x = 'Match Probability Threshold', y = 'Value', colour = 'Metric'
    ) +
    ggplot2::theme_minimal()
}

#' Plot ROC Curve
#'
#' Draws a receiver operating characteristic curve from the data
#' produced by [il_roc()].
#'
#' @param object An `il_roc` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_roc <- function(object, ...) {
  rlang::check_installed('ggplot2')
  ggplot2::ggplot(object, ggplot2::aes(
    x = .data[['fpr']], y = .data[['tpr']]
  )) +
    ggplot2::geom_line(linewidth = 0.8, colour = 'steelblue') +
    ggplot2::geom_abline(
      intercept = 0, slope = 1, linetype = 'dashed',
      colour = 'grey50'
    ) +
    ggplot2::labs(
      title = 'ROC Curve',
      x = 'False Positive Rate', y = 'True Positive Rate'
    ) +
    ggplot2::coord_equal() +
    ggplot2::theme_minimal()
}

#' Plot Precision–Recall Curve
#'
#' Draws a precision–recall curve from the data produced by
#' [il_precision_recall()].
#'
#' @param object An `il_precision_recall` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_precision_recall <- function(object, ...) {
  rlang::check_installed('ggplot2')
  ggplot2::ggplot(object, ggplot2::aes(
    x = .data[['recall']], y = .data[['precision']]
  )) +
    ggplot2::geom_line(linewidth = 0.8, colour = 'steelblue') +
    ggplot2::geom_point(size = 1.5, colour = 'steelblue') +
    ggplot2::labs(
      title = 'Precision\u2013Recall Curve',
      x = 'Recall', y = 'Precision'
    ) +
    ggplot2::ylim(0, 1) +
    ggplot2::theme_minimal()
}

#' Plot Unlinkables Curve
#'
#' Draws the proportion of records that cannot be linked at each
#' match-probability threshold, from data produced by
#' [il_unlinkables()].
#'
#' @param object An `il_unlinkables` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_unlinkables <- function(object, ...) {
  rlang::check_installed('ggplot2')
  ggplot2::ggplot(object, ggplot2::aes(
    x = .data[['threshold']], y = .data[['pct_unlinkable']]
  )) +
    ggplot2::geom_line(linewidth = 0.8, colour = 'steelblue') +
    ggplot2::geom_area(alpha = 0.15, fill = 'steelblue') +
    ggplot2::labs(
      title = 'Unlinkable Records by Threshold',
      x = 'Match Probability Threshold',
      y = 'Proportion Unlinkable'
    ) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(x * 100), '%')) +
    ggplot2::theme_minimal()
}

#' Plot Column Completeness
#'
#' Draws a grouped bar chart of non-null percentages per column, from
#' data produced by [il_completeness()].
#'
#' @param object An `il_completeness` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_completeness <- function(object, ...) {
  rlang::check_installed('ggplot2')
  ggplot2::ggplot(object, ggplot2::aes(
    x = .data[['column']], y = .data[['pct_non_null']],
    fill = .data[['table']]
  )) +
    ggplot2::geom_col(position = 'dodge') +
    ggplot2::labs(
      title = 'Column Completeness',
      x = 'Column', y = '% Non-Null', fill = 'Table'
    ) +
    ggplot2::theme_minimal()
}
