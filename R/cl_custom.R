#' Custom SQL Comparison
#'
#' Creates a comparison level from a raw SQL expression. Use this when
#' none of the built-in `cl_*()` helpers fit. The SQL should reference
#' `l.` and `r.` prefixed column names for the left and right records.
#' Analogous to [gt::md()] — a tagged-string helper with processing
#' semantics.
#'
#' @param sql_expr A character string containing a valid SQL expression.
#' @param ... Reserved for future use.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(score, cl_custom("l.score + r.score > 10"))
#' }
cl_custom <- function(sql_expr, ...) {
  if (!is.character(sql_expr) || length(sql_expr) != 1L) {
    cli::cli_abort("{.arg sql_expr} must be a single character string.")
  }
  structure(
    list(method = "custom", sql_expr = sql_expr,
         is_null_level = FALSE, is_else_level = FALSE),
    class = "il_comparison_level"
  )
}
