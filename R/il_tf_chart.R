#' Term Frequency Adjustment Chart
#'
#' Visualises the distribution of term frequencies for a column in the
#' model. Shows how individual values shift the match weight via the TF
#' adjustment (rare values boost the weight; common values penalise it).
#'
#' @param model A trained `il_model` object with `term_frequency = TRUE`
#'   enabled for at least one comparison column.
#' @param col A character string naming the column to plot.
#' @param n_most_freq Number of most-frequent values to label. Default 10.
#' @param n_least_freq Number of least-frequent values to label. Default 5.
#'
#' @return A `ggplot` object.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(fake_1000, spec = spec, con = con)
#' il_tf_chart(model, 'first_name')
#' }
il_tf_chart <- function(model, col, n_most_freq = 10L, n_least_freq = 5L) {
  if (!inherits(model, 'il_model')) {
    cli::cli_abort(
      '{.arg model} must be an {.cls il_model}, not {.obj_type_friendly {model}}.',
      class = 'il_error_type'
    )
  }
  if (!is.character(col) || length(col) != 1L) {
    cli::cli_abort(
      '{.arg col} must be a single column name string.',
      class = 'il_error_type'
    )
  }

  con <- model$con
  tf_tbl <- paste0('__il_tf_', col)

  if (is.null(con) || !DBI::dbExistsTable(con, tf_tbl)) {
    cli::cli_abort(
      'No term frequency table found for column {.field {col}}. \\
       Ensure {.code term_frequency = TRUE} is set in the comparison \\
       and the model has been trained.',
      class = 'il_error_type'
    )
  }

  tf_col <- paste0('tf_', col)
  tf_data <- DBI::dbGetQuery(
    con,
    glue::glue('SELECT {col} AS value, {tf_col} AS tf FROM {tf_tbl} ORDER BY {tf_col} DESC')
  )

  if (nrow(tf_data) == 0L) {
    cli::cli_abort('Term frequency table {.field {tf_tbl}} is empty.')
  }

  # Compute the TF weight adjustment: log2(tf / median_tf)
  # Values with TF above median get negative adjustment (penalised)
  # Values with TF below median get positive adjustment (boosted)
  median_tf <- stats::median(tf_data$tf, na.rm = TRUE)
  tf_data$weight_adj <- log2(median_tf / tf_data$tf)

  # Label the most and least frequent
  n_rows <- nrow(tf_data)
  tf_data$label <- ''
  top_n <- min(n_most_freq, n_rows)
  bot_n <- min(n_least_freq, n_rows)
  tf_data$label[seq_len(top_n)] <- tf_data$value[seq_len(top_n)]
  if (bot_n > 0L && n_rows > top_n) {
    bot_idx <- seq.int(n_rows - bot_n + 1L, n_rows)
    tf_data$label[bot_idx] <- tf_data$value[bot_idx]
  }

  tf_data$rank <- seq_len(n_rows)

  tf_data |>
    ggplot2::ggplot() +
    ggplot2::geom_col(ggplot2::aes(x = .data[['rank']], y = .data[['tf']]), fill = '#4682B4') +
    ggplot2::geom_text(
      data = tf_data[tf_data$label != '', ],
      ggplot2::aes(x = .data[['rank']], y = .data[['tf']], label = .data[['label']]),
      angle = 45, hjust = -0.1, vjust = 0, size = 2.5
    ) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(x * 100, 1), '%')) +
    ggplot2::labs(
      title = paste('Term Frequency Distribution:', col),
      x = paste('Values of', col, '(ranked by frequency)'),
      y = 'Term Frequency'
    ) +
    ggplot2::theme_minimal()
}

#' Comparator Score Bar Chart
#'
#' Visualises the output of [il_string_similarity()] as a horizontal bar
#' chart, making it easy to compare multiple string-distance metrics at a
#' glance.
#'
#' @param object An `il_string_similarity` tibble (the return value of
#'   [il_string_similarity()]).
#' @param ... Additional arguments (currently unused).
#'
#' @return A `ggplot` object.
#' @exportS3Method ggplot2::autoplot
#'
#' @examples
#' \dontrun{
#' library(ggplot2)
#' autoplot(il_string_similarity('John', 'Jon'))
#' }
autoplot.il_string_similarity <- function(object, ...) {
  # Pivot to long form
  long <- tibble::tibble(
    metric = names(object),
    score = as.numeric(object[1, ])
  )
  # Normalise levenshtein to [0, 1] for visual comparison (invert so lower = more similar)
  lv_idx <- which(long$metric == 'levenshtein')
  if (length(lv_idx) == 1L && !is.na(long$score[lv_idx])) {
    max_lv <- max(long$score[lv_idx], 1)
    long$score[lv_idx] <- 1 - long$score[lv_idx] / (max_lv + 1)
    long$metric[lv_idx] <- 'levenshtein\n(normalised)'
  }

  long$metric <- factor(long$metric, levels = rev(long$metric))

  long |>
    ggplot2::ggplot() +
    ggplot2::geom_col(ggplot2::aes(
      x = .data[['score']], y = .data[['metric']], fill = .data[['score']]
    ), show.legend = FALSE) +
    ggplot2::geom_text(ggplot2::aes(
      x = .data[['score']], y = .data[['metric']],
      label = round(.data[['score']], 3)
    ), hjust = -0.1, size = 3.5) +
    ggplot2::scale_fill_gradient(low = '#B22222', high = '#228B22') +
    ggplot2::scale_x_continuous(limits = c(0, 1.15)) +
    ggplot2::labs(
      title = 'String Similarity Scores',
      x = 'Score (higher = more similar)',
      y = NULL
    ) +
    ggplot2::theme_minimal()
}
