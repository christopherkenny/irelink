#' Date Difference Comparison
#'
#' Creates comparison levels based on the absolute difference between two
#' dates. Thresholds should use the unit helpers [days()], [months()], or
#' [years()] for self-documenting, unit-safe specifications. Bare numerics
#' are interpreted as days.
#'
#' @param ... Duration thresholds created by [days()], [months()], or
#'   [years()], ordered from strictest to most lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(days(30), days(365)))
#'
#' # Mix units freely
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(months(1), years(1)))
#' }
cl_date_diff <- function(...) {
  cli::cli_warn("Function {.fn cl_date_diff} is not yet implemented.")
  invisible(NULL)
}
