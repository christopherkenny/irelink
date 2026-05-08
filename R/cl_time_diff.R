#' Time Difference Comparison
#'
#' Creates comparison levels based on the absolute difference between two
#' datetime (timestamp) values. Thresholds should use the unit helpers
#' [seconds()], [minutes()], [hours()], [days()], [months()], or [years()]
#' for self-documenting, unit-safe specifications. Bare numerics are
#' interpreted as seconds.
#'
#' This extends [cl_date_diff()] to support sub-day precision for timestamp
#' columns. Use `cl_date_diff()` for date-only columns.
#'
#' @param ... Duration thresholds created by [seconds()], [minutes()],
#'   [hours()], [days()], [months()], or [years()], ordered from strictest
#'   to most lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(timestamp, cl_time_diff(minutes(5), hours(1)))
#'
#' # Mix units freely
#' il_spec() |>
#'   il_compare(timestamp, cl_time_diff(seconds(30), minutes(10), hours(2)))
cl_time_diff <- function(...) {
  args <- list(...)
  if (length(args) == 0L) {
    cli::cli_abort('{.fn cl_time_diff} requires at least one threshold.')
  }
  valid_units <- c('seconds', 'minutes', 'hours', 'days', 'months', 'years')
  thresholds <- vapply(args, function(a) {
    if (is.numeric(a) && length(a) == 1L) {
      check_unit_input(a, 'cl_time_diff')
      return(a)
    }
    if (is.list(a) && !is.null(a$unit)) {
      if (!a$unit %in% valid_units) {
        cli::cli_abort(
          '{.fn cl_time_diff} accepts {.or {.val {valid_units}}} units, not {.val {a$unit}}.'
        )
      }
      return(a$value)
    }
    cli::cli_abort('Invalid threshold for {.fn cl_time_diff}.')
  }, numeric(1))
  units <- vapply(args, function(a) {
    if (is.numeric(a) && length(a) == 1L) {
      return('seconds')
    }
    a$unit
  }, character(1))
  seconds_values <- mapply(time_diff_to_seconds, thresholds, units)
  if (length(seconds_values) > 1L && is.unsorted(seconds_values)) {
    cli::cli_warn(
      'Thresholds for {.fn cl_time_diff} should be in ascending order; re-ordering.'
    )
    ord <- order(seconds_values)
    thresholds <- thresholds[ord]
    units <- units[ord]
  }
  new_comparison_level('time_diff', thresholds = thresholds, units = units)
}
