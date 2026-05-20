#' Custom SQL Comparison
#'
#' Creates a comparison level from a raw SQL expression. Use this when
#' none of the built-in `cl_*()` helpers fit. The SQL should reference
#' `l.` and `r.` prefixed column names for the left and right records.
#' This is a tagged-string helper with processing semantics.
#'
#' @param sql_expr A character string containing a valid SQL expression.
#' @param ... Reserved for future use.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(score, cl_custom('l.score + r.score > 10'))
cl_custom <- function(sql_expr, ...) {
  if (!is.character(sql_expr) || length(sql_expr) != 1L) {
    cli::cli_abort('{.arg sql_expr} must be a single character string.')
  }
  new_comparison_level('custom', sql_expr = sql_expr)
}

#' Literal Value Comparison
#'
#' Creates a comparison level that checks whether a column equals a
#' fixed literal value on the left record, right record, or both. This is
#' useful as a gate inside [cl_levels()] to restrict a comparison to
#' records with a known value (e.g., only compare names when
#' `country = 'US'`).
#'
#' @param value A scalar value to compare against. Character values are
#'   quoted in the generated SQL. Numerics are not.
#' @param side Which record to check: `'both'` (default), `'left'`, or
#'   `'right'`.
#'
#' @return A comparison-level object for use in [il_compare()] or
#'   [cl_levels()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(
#'     country,
#'     cl_levels(
#'       cl_null(),
#'       cl_literal('US', side = 'both'),
#'       cl_exact(),
#'       cl_else()
#'     )
#'   )
cl_literal <- function(value, side = c('both', 'left', 'right')) {
  side <- match.arg(side)
  if (length(value) != 1L) {
    cli::cli_abort('{.arg value} must be a scalar value.')
  }
  if (is.na(value)) {
    val_sql <- 'NULL'
    op <- 'IS'
  } else {
    val_sql <- if (is.character(value)) {
      paste0("'", gsub("'", "''", value, fixed = TRUE), "'")
    } else {
      as.character(value)
    }
    op <- '='
  }
  sql_expr <- switch(
    side,
    'both' = paste0(
      'l.{col} ',
      op,
      ' ',
      val_sql,
      ' AND r.{col} ',
      op,
      ' ',
      val_sql
    ),
    'left' = paste0('l.{col} ', op, ' ', val_sql),
    'right' = paste0('r.{col} ', op, ' ', val_sql)
  )
  cl_custom(sql_expr)
}
