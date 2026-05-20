#' Quick Match-Weights Plot for a Model
#'
#' Produces a ready-made chart from a trained model. By default draws
#' the match-weights bar chart. Set `type = "parameters"` for an m / u
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
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_model <- function(object, type = c('weights', 'parameters'), ...) {
  type <- match.arg(type)

  if (type == 'parameters') {
    wt <- il_weights(object)
    long <- rbind(
      tibble::tibble(
        comparison = wt$comparison,
        gamma_level = wt$gamma_level,
        probability = wt$m_prob,
        parameter = 'm'
      ),
      tibble::tibble(
        comparison = wt$comparison,
        gamma_level = wt$gamma_level,
        probability = wt$u_prob,
        parameter = 'u'
      )
    )
    return(
      long |>
        ggplot2::ggplot() +
        ggplot2::geom_col(
          ggplot2::aes(
            x = .data[['comparison']],
            y = .data[['probability']],
            fill = .data[['parameter']]
          ),
          position = 'dodge'
        ) +
        ggplot2::facet_wrap(~ .data[['gamma_level']]) +
        ggplot2::labs(
          title = 'Model Parameters',
          x = 'Comparison',
          y = 'Probability',
          fill = 'Parameter'
        ) +
        ggplot2::theme_minimal() +
        ggplot2::theme(
          axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
        )
    )
  }

  wt <- il_weights(object)
  wt |>
    ggplot2::ggplot() +
    ggplot2::geom_col(
      ggplot2::aes(
        x = .data[['comparison']],
        y = .data[['weight']],
        fill = factor(.data[['gamma_level']])
      ),
      position = 'dodge'
    ) +
    ggplot2::labs(
      title = 'Match Weights',
      x = 'Comparison',
      y = 'Weight (log2)',
      fill = 'Gamma Level'
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

#' Quick Plot for Scored Pairs
#'
#' Produces a match-weight histogram from scored pairs, or a waterfall
#' chart for a single pair when `which` is provided. This is a
#' convenience wrapper around [ggplot2::ggplot()]. For full control,
#' build a plot directly from the prediction result or from
#' [il_waterfall()].
#'
#' @param object An `il_compared` tibble from [predict.il_model()].
#' @param which An optional integer index. If provided, produces a
#'   waterfall chart for that pair. If `NULL` (default), produces a
#'   histogram.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_compared <- function(object, which = NULL, ...) {
  if (!is.null(which)) {
    wf <- il_waterfall(object, which = which)
    return(
      wf |>
        ggplot2::ggplot() +
        ggplot2::geom_rect(ggplot2::aes(
          xmin = pmin(.data[['start']], .data[['end']]),
          xmax = pmax(.data[['start']], .data[['end']]),
          ymin = .data[['order']] - 0.4,
          ymax = .data[['order']] + 0.4,
          fill = .data[['direction']]
        )) +
        ggplot2::geom_vline(
          xintercept = 0,
          linewidth = 0.3,
          colour = 'grey70'
        ) +
        ggplot2::scale_y_continuous(
          breaks = wf$order,
          labels = wf$step
        ) +
        ggplot2::labs(
          title = 'Waterfall',
          x = 'Match Weight (log2 odds)',
          y = 'Step',
          fill = 'Component'
        ) +
        ggplot2::theme_minimal()
    )
  }
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_histogram(
      ggplot2::aes(x = .data[['match_weight']]),
      binwidth = 1
    ) +
    ggplot2::labs(
      title = 'Match Weight Distribution',
      x = 'Match Weight (log2)',
      y = 'Count'
    ) +
    ggplot2::theme_minimal()
}

#' @exportS3Method ggplot2::autoplot
autoplot.il_compared_lazy <- function(object, which = NULL, ...) {
  autoplot.il_compared(collect_il_compared_lazy(object), which = which, ...)
}

#' Plot Accuracy Metrics Across Thresholds
#'
#' Draws precision, recall, and F1 against the match-probability
#' threshold. The data is produced by [il_accuracy()].
#'
#' @param object An `il_accuracy` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_accuracy <- function(object, ...) {
  long <- rbind(
    tibble::tibble(
      threshold = object$threshold,
      value = object$precision,
      metric = 'Precision'
    ),
    tibble::tibble(
      threshold = object$threshold,
      value = object$recall,
      metric = 'Recall'
    ),
    tibble::tibble(
      threshold = object$threshold,
      value = object$f1,
      metric = 'F1'
    )
  )
  long |>
    ggplot2::ggplot() +
    ggplot2::geom_line(ggplot2::aes(
      x = .data[['threshold']],
      y = .data[['value']],
      colour = .data[['metric']]
    )) +
    ggplot2::labs(
      title = 'Accuracy Metrics by Threshold',
      x = 'Match Probability Threshold',
      y = 'Value',
      colour = 'Metric'
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
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_roc <- function(object, ...) {
  object <- object[order(object$fpr, object$tpr), ]
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_line(ggplot2::aes(
      x = .data[['fpr']],
      y = .data[['tpr']]
    )) +
    ggplot2::geom_abline(
      intercept = 0,
      slope = 1,
      linetype = 'dashed',
      colour = 'grey50'
    ) +
    ggplot2::labs(
      title = 'ROC Curve',
      x = 'False Positive Rate',
      y = 'True Positive Rate'
    ) +
    ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
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
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_precision_recall <- function(object, ...) {
  object <- object[order(object$recall, -object$precision), ]
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_line(ggplot2::aes(
      x = .data[['recall']],
      y = .data[['precision']]
    )) +
    ggplot2::geom_point(ggplot2::aes(
      x = .data[['recall']],
      y = .data[['precision']]
    )) +
    ggplot2::labs(
      title = 'Precision\u2013Recall Curve',
      x = 'Recall',
      y = 'Precision'
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
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_unlinkables <- function(object, ...) {
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_line(ggplot2::aes(
      x = .data[['threshold']],
      y = .data[['pct_unlinkable']]
    )) +
    ggplot2::labs(
      title = 'Unlinkable Records by Threshold',
      x = 'Match Probability Threshold',
      y = 'Proportion Unlinkable'
    ) +
    ggplot2::scale_y_continuous(labels = \(x) paste0(round(x * 100), '%')) +
    ggplot2::theme_minimal()
}

#' Plot Blocking Rule Pair Counts
#'
#' Draws a horizontal bar chart of candidate pairs generated by each
#' blocking rule, from data produced by [il_count_pairs()].
#'
#' @param object An `il_count_pairs` tibble.
#' @param type One of `"additional"` (default) to show the incremental
#'   pairs each rule adds beyond those already covered by earlier rules,
#'   or `"raw"` to show the total pairs each rule generates independently.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_count_pairs <- function(
  object,
  type = c('additional', 'raw'),
  ...
) {
  type <- match.arg(type)
  object$rule_wrapped <- vapply(
    object$rule,
    function(x) {
      lines <- strwrap(x, width = 40)
      if (length(lines) > 2L) {
        lines <- c(lines[1:2])
        lines[2L] <- paste0(substr(lines[2L], 1, 37), '...')
      }
      paste(lines, collapse = '\n')
    },
    character(1)
  )
  if (type == 'additional') {
    n <- nrow(object)
    object$xmin <- c(0, object$cumulative_pairs[-n])
    object$xmax <- object$cumulative_pairs
    # y positions: first rule at top (highest y)
    object$ypos <- rev(seq_len(n))
    p <- object |>
      ggplot2::ggplot() +
      ggplot2::geom_rect(ggplot2::aes(
        xmin = .data[['xmin']],
        xmax = .data[['xmax']],
        ymin = .data[['ypos']] - 0.4,
        ymax = .data[['ypos']] + 0.4
      )) +
      ggplot2::scale_y_continuous(
        breaks = object$ypos,
        labels = object$rule_wrapped
      ) +
      ggplot2::labs(
        title = 'Cumulative Pairs by Blocking Rule',
        x = 'Pairs',
        y = NULL
      ) +
      ggplot2::scale_x_continuous(labels = \(x) {
        formatC(x, format = 'f', big.mark = ',', digits = 0)
      }) +
      ggplot2::theme_minimal()
  } else {
    object$rule_wrapped <- stats::reorder(object$rule_wrapped, object$n_pairs)
    p <- object |>
      ggplot2::ggplot() +
      ggplot2::geom_col(ggplot2::aes(
        x = .data[['rule_wrapped']],
        y = .data[['n_pairs']]
      )) +
      ggplot2::coord_flip() +
      ggplot2::labs(
        title = 'Candidate Pairs per Blocking Rule',
        x = NULL,
        y = 'Pairs Generated'
      ) +
      ggplot2::scale_y_continuous(labels = \(x) {
        formatC(x, format = 'f', big.mark = ',', digits = 0)
      }) +
      ggplot2::theme_minimal()
  }
  p
}

#' Plot Column Value Profiles
#'
#' Draws a faceted bar chart of value frequencies per column, from data
#' produced by [il_profile()].
#'
#' @param object An `il_profile` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_profile <- function(object, ...) {
  object$facet_value <- paste(object$column, object$value, sep = '___')
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_col(ggplot2::aes(
      x = stats::reorder(.data[['facet_value']], .data[['n']]),
      y = .data[['n']]
    )) +
    ggplot2::coord_flip() +
    ggplot2::facet_wrap(~ .data[['column']], scales = 'free') +
    ggplot2::scale_x_discrete(labels = \(x) sub('^.*___', '', x)) +
    ggplot2::labs(
      title = 'Column Value Frequencies',
      x = 'Value',
      y = 'Count'
    ) +
    ggplot2::theme_minimal()
}

#' Plot EM Training History
#'
#' Draws parameter estimates across EM iterations, faceted by comparison,
#' from data produced by [il_training_history()].
#'
#' @param object An `il_training_history` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_training_history <- function(object, ...) {
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_line(ggplot2::aes(
      x = .data[['iteration']],
      y = .data[['value']],
      colour = factor(.data[['session']]),
      linetype = factor(.data[['gamma_level']]),
      group = interaction(.data[['session']], .data[['gamma_level']])
    )) +
    ggplot2::geom_point(ggplot2::aes(
      x = .data[['iteration']],
      y = .data[['value']],
      colour = factor(.data[['session']]),
      group = interaction(.data[['session']], .data[['gamma_level']])
    )) +
    ggplot2::facet_wrap(~ .data[['comparison']], scales = 'free_y') +
    ggplot2::labs(
      title = 'EM Training History',
      x = 'Iteration',
      y = 'm probability',
      colour = 'EM session',
      linetype = 'Gamma level'
    ) +
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
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_completeness <- function(object, ...) {
  object |>
    ggplot2::ggplot() +
    ggplot2::geom_col(
      ggplot2::aes(
        x = .data[['column']],
        y = .data[['pct_non_null']],
        fill = .data[['table']]
      ),
      position = 'dodge'
    ) +
    ggplot2::labs(
      title = 'Column Completeness',
      x = 'Column',
      y = '% Non-Null',
      fill = 'Table'
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

#' Plot Batch Comparator Scores
#'
#' @param object An `il_comparator_score` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
autoplot.il_comparator_score <- function(object, ...) {
  metric_cols <- intersect(
    c('jaro_winkler', 'jaro', 'jaccard', 'cosine'),
    names(object)
  )
  if (length(metric_cols) == 0L) {
    cli::cli_abort('No similarity metric columns found.')
  }

  long <- reshape_long(object, metric_cols, 'metric', 'score')

  long |>
    ggplot2::ggplot() +
    ggplot2::geom_histogram(
      ggplot2::aes(x = .data$score),
      bins = 30,
      fill = '#2171b5',
      colour = 'white'
    ) +
    ggplot2::facet_wrap(~metric, scales = 'free_y') +
    ggplot2::labs(
      x = 'Similarity Score',
      y = 'Count',
      title = 'Comparator Score Distribution'
    ) +
    ggplot2::theme_minimal()
}

#' Plot Comparison Vector Distribution
#'
#' @param object An `il_comparison_vectors` tibble.
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object showing the top comparison patterns by
#'   frequency.
#' @exportS3Method ggplot2::autoplot
autoplot.il_comparison_vectors <- function(object, ...) {
  gamma_cols <- grep('^gamma_', names(object), value = TRUE)

  object$pattern <- apply(object[, gamma_cols], 1, function(row) {
    paste(row, collapse = '-')
  })

  top <- utils::head(object[order(-object$count), ], 20)
  top$pattern <- factor(top$pattern, levels = rev(top$pattern))

  top |>
    ggplot2::ggplot() +
    ggplot2::geom_col(
      ggplot2::aes(x = .data$count, y = .data$pattern),
      fill = '#2171b5'
    ) +
    ggplot2::labs(
      x = 'Count',
      y = 'Comparison Vector (gamma pattern)',
      title = 'Comparison Vector Distribution (Top 20)'
    ) +
    ggplot2::theme_minimal()
}

#' Comparator Score Bar Chart
#'
#' Visualizes the output of [il_string_similarity()] as a horizontal bar
#' chart, making it easy to compare multiple string-distance metrics at a
#' glance.
#'
#' @param object An `il_string_similarity` tibble (the return value of
#'   [il_string_similarity()]).
#' @param ... Additional arguments (currently unused).
#'
#' @return A [ggplot2::ggplot()] object.
#' @exportS3Method ggplot2::autoplot
#'
#' @examples
#' ggplot2::autoplot(il_string_similarity('John', 'Jon'))
autoplot.il_string_similarity <- function(object, ...) {
  long <- tibble::tibble(
    metric = names(object),
    score = as.numeric(object[1, ])
  )

  lv_idx <- which(long$metric == 'levenshtein')
  if (length(lv_idx) == 1L && !is.na(long$score[lv_idx])) {
    max_lv <- max(long$score[lv_idx], 1)
    long$score[lv_idx] <- 1 - long$score[lv_idx] / (max_lv + 1)
    long$metric[lv_idx] <- 'levenshtein\n(normalised)'
  }

  long$metric <- factor(long$metric, levels = rev(long$metric))

  long |>
    ggplot2::ggplot() +
    ggplot2::geom_col(
      ggplot2::aes(
        x = .data[['score']],
        y = .data[['metric']],
        fill = .data[['score']]
      ),
      show.legend = FALSE
    ) +
    ggplot2::geom_text(
      ggplot2::aes(
        x = .data[['score']],
        y = .data[['metric']],
        label = round(.data[['score']], 3)
      ),
      hjust = -0.1,
      size = 3.5
    ) +
    ggplot2::scale_fill_gradient(low = '#B22222', high = '#228B22') +
    ggplot2::scale_x_continuous(limits = c(0, 1.15)) +
    ggplot2::labs(
      title = 'String Similarity Scores',
      x = 'Score (higher = more similar)',
      y = NULL
    ) +
    ggplot2::theme_minimal()
}
