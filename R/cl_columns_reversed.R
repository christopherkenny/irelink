#' Swap Detection for Two Columns
#'
#' Creates a comparison level that fires when two column values are
#' transposed between the left and right records (e.g., first name and
#' surname accidentally swapped). This is a standalone equivalent of
#' splink's `ColumnsReversedLevel`.
#'
#' Use inside [cl_levels()] to add a swap-detection level to a custom
#' comparison. For a ready-made name comparison that already includes
#' swap detection, see [cl_forename_surname()].
#'
#' @param col_name_2 Name of the second column (character). The first
#'   column is the one passed to [il_compare()].
#' @param symmetrical Logical. If `TRUE`, checks both directions:
#'   `l.col1 = r.col2 AND l.col2 = r.col1`.
#'   If `FALSE` (default), checks one direction only:
#'   `l.col1 = r.col2`.
#'
#' @return A comparison-level object for use in [il_compare()] or
#'   [cl_levels()].
#' @export
#'
#' @examples
#' # Detect swapped first/last names inside a custom comparison
#' il_spec() |>
#'   il_compare(
#'     first_name,
#'     cl_levels(
#'       cl_null(),
#'       cl_exact(),
#'       cl_columns_reversed('surname', symmetrical = TRUE),
#'       cl_else()
#'     )
#'   )
cl_columns_reversed <- function(col_name_2, symmetrical = FALSE) {
  if (!is.character(col_name_2) || length(col_name_2) != 1L) {
    cli::cli_abort('{.arg col_name_2} must be a single character string.')
  }
  if (!is.logical(symmetrical) || length(symmetrical) != 1L) {
    cli::cli_abort('{.arg symmetrical} must be a single logical value.')
  }

  if (symmetrical) {
    sql <- paste0(
      'l.{col} = r.', col_name_2,
      ' AND l.', col_name_2, ' = r.{col}'
    )
  } else {
    sql <- paste0('l.{col} = r.', col_name_2)
  }

  cl_custom(sql)
}
