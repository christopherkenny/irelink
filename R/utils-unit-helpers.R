# Unit helpers -- tagged-value constructors for self-documenting thresholds.
# Inspired by gt's px(), pct(), and md().
#
# NOTE: days(), months(), and years() share names with lubridate exports.
# We accept the namespace collision because:
#   1. irelink's versions are tagged-value constructors, not durations.
#   2. Users will rarely load both irelink and lubridate simultaneously.
#   3. Explicit namespacing (irelink::days()) resolves any ambiguity.

# Internal validator for unit helper inputs
check_unit_input <- function(n, unit) {
  if (
    !is.numeric(n) || length(n) != 1L || is.na(n) || is.infinite(n) || is.nan(n)
  ) {
    cli::cli_abort(
      '{.arg n} must be a single finite numeric value, not {.obj_type_friendly {n}}.'
    )
  }
  if (n < 0) {
    cli::cli_abort('{.arg n} must be non-negative for {.fn {unit}}.')
  }
  invisible(n)
}

#' @export
print.il_days <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' @export
print.il_months <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' @export
print.il_years <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' @export
print.il_km <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' @export
print.il_mi <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

format_unit_helper <- function(x) {
  paste0(x$value, ' ', x$unit)
}


#' Create a Duration in Days
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of days. Use inside
#' [cl_date_diff()] for self-documenting, unit-safe thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_days`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(days(30), days(365)))
days <- function(n) {
  check_unit_input(n, 'days')
  structure(list(value = n, unit = 'days'), class = 'il_days')
}

#' Create a Duration in Months
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of months. Use inside [cl_date_diff()] for self-documenting
#' thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_months`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(months(1), months(12)))
months <- function(n) {
  check_unit_input(n, 'months')
  structure(list(value = n, unit = 'months'), class = 'il_months')
}

#' Create a Duration in Years
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of years. Use inside [cl_date_diff()] for self-documenting thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_years`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(years(1)))
years <- function(n) {
  check_unit_input(n, 'years')
  structure(list(value = n, unit = 'years'), class = 'il_years')
}

#' Create a Duration in Hours
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of hours. Use inside [cl_time_diff()] for self-documenting,
#' unit-safe thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_hours`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(timestamp, cl_time_diff(hours(2), hours(24)))
hours <- function(n) {
  check_unit_input(n, 'hours')
  structure(list(value = n, unit = 'hours'), class = 'il_hours')
}

#' Create a Duration in Minutes
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of minutes. Use inside [cl_time_diff()] for self-documenting
#' thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_minutes`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(timestamp, cl_time_diff(minutes(5), minutes(60)))
minutes <- function(n) {
  check_unit_input(n, 'minutes')
  structure(list(value = n, unit = 'minutes'), class = 'il_minutes')
}

#' Create a Duration in Seconds
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of seconds. Use inside [cl_time_diff()] for self-documenting
#' thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_seconds`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(timestamp, cl_time_diff(seconds(30), seconds(300)))
seconds <- function(n) {
  check_unit_input(n, 'seconds')
  structure(list(value = n, unit = 'seconds'), class = 'il_seconds')
}

#' @export
print.il_hours <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' @export
print.il_minutes <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' @export
print.il_seconds <- function(x, ...) {
  cat(format_unit_helper(x), '\n')
  invisible(x)
}

#' Create a Distance in Kilometres
#'
#' A tagged-value constructor that marks a numeric threshold as a distance
#' in kilometres. Use inside [cl_distance_km()] for self-documenting
#' thresholds.
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_km`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(c(lat, lon), cl_distance_km(km(5), km(50)))
km <- function(n) {
  check_unit_input(n, 'km')
  structure(list(value = n, unit = 'km'), class = 'il_km')
}

#' Create a Distance in Miles
#'
#' A tagged-value constructor that marks a numeric threshold as a distance
#' in miles. Converted to kilometres internally by [cl_distance_km()].
#'
#' @param n A non-negative numeric value.
#'
#' @return A tagged numeric with class `il_mi`.
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(c(lat, lon), cl_distance_km(mi(3), mi(30)))
mi <- function(n) {
  check_unit_input(n, 'mi')
  structure(list(value = n, unit = 'mi'), class = 'il_mi')
}
