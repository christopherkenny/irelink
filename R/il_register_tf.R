#' Register Pre-Computed Term Frequency Tables
#'
#' Allows you to supply pre-computed term frequency lookup tables
#' instead of having them computed automatically from the data. This
#' is useful when you have production TF tables from a larger dataset
#' or want to reuse TF values across multiple linkage runs.
#'
#' The supplied data must have exactly two columns: the value column
#' (named the same as the comparison column) and the frequency column
#' (named `tf_<col>`).
#'
#' @param model An `il_model` object.
#' @param col Character name of the comparison column.
#' @param tf_data A data frame with columns `<col>` and `tf_<col>`.
#' @param overwrite Logical. If `TRUE`, overwrite an existing TF table
#'   for this column. Defaults to `FALSE`.
#'
#' @return The updated model, with the TF table registered in the database.
#' @export
#'
#' @examples
#' \dontrun{
#' # Suppose you have pre-computed TF for first_name
#' tf <- data.frame(
#'   first_name = c('John', 'Jane', 'Bob'),
#'   tf_first_name = c(0.15, 0.10, 0.05)
#' )
#' model <- il_register_tf(model, 'first_name', tf)
#' }
il_register_tf <- function(model, col, tf_data, overwrite = FALSE) {
  validate_il_model(model)
  if (!is.character(col) || length(col) != 1L) {
    cli::cli_abort('{.arg col} must be a single character string.')
  }
  if (!col %in% model$data$columns) {
    cli::cli_abort('Column {.field {col}} not found in the model data.')
  }

  tf_col_name <- paste0('tf_', col)
  expected_cols <- c(col, tf_col_name)

  if (!all(expected_cols %in% names(tf_data))) {
    cli::cli_abort(
      '{.arg tf_data} must have columns {.val {expected_cols}}, \\
       got {.val {names(tf_data)}}.'
    )
  }
  if (anyNA(tf_data[[col]])) {
    cli::cli_abort(
      '{.arg tf_data} value column {.field {col}} must not contain missing values.'
    )
  }
  if (anyDuplicated(tf_data[[col]]) > 0L) {
    cli::cli_abort(
      '{.arg tf_data} value column {.field {col}} must contain unique values.'
    )
  }
  tf_values <- tf_data[[tf_col_name]]
  if (
    !is.numeric(tf_values) ||
      anyNA(tf_values) ||
      any(!is.finite(tf_values)) ||
      any(tf_values <= 0 | tf_values > 1)
  ) {
    cli::cli_abort(
      '{.arg tf_data} frequency column {.field {tf_col_name}} must contain finite probabilities with 0 < value <= 1.'
    )
  }

  con <- model$con
  if (is.null(model$data$tf_tables)) {
    model$data$tf_tables <- list()
  }
  tf_tbl <- model$data$tf_tables[[col]] %||% il_table_name(model, 'tf', col)

  tbl_exists <- tf_tbl %in% DBI::dbListTables(con)
  if (tbl_exists && !overwrite) {
    cli::cli_abort(
      'TF table {.val {tf_tbl}} already exists. \\
       Use {.code overwrite = TRUE} to replace it.'
    )
  }

  DBI::dbExecute(
    con,
    glue::glue(
      'DROP TABLE IF EXISTS {sql_quote_identifier(tf_tbl)}'
    )
  )
  DBI::dbWriteTable(con, tf_tbl, tf_data[, expected_cols])

  model$data$tf_tables[[col]] <- tf_tbl
  model <- il_track_table(model, tf_tbl, owner = 'model')

  model
}
