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
  args <- list(...)
  if (length(args) == 0L) {
    cli::cli_abort("{.fn cl_date_diff} requires at least one threshold.")
  }
  valid_units <- c("days", "months", "years")
  thresholds <- vapply(args, function(a) {
    if (is.numeric(a) && length(a) == 1L) return(a)
    if (is.list(a) && !is.null(a$unit)) {
      if (!a$unit %in% valid_units) {
        cli::cli_abort(
          "{.fn cl_date_diff} accepts {.or {.val {valid_units}}} units, not {.val {a$unit}}."
        )
      }
      return(a$value)
    }
    cli::cli_abort("Invalid threshold for {.fn cl_date_diff}.")
  }, numeric(1))
  units <- vapply(args, function(a) {
    if (is.numeric(a) && length(a) == 1L) return("days")
    a$unit
  }, character(1))
  new_comparison_level("date_diff", thresholds = thresholds, units = units)
}
