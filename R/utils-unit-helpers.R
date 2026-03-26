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
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || is.infinite(n) || is.nan(n)) {
    cli::cli_abort("{.arg n} must be a single finite numeric value, not {.obj_type_friendly {n}}.")
  }
  if (n < 0) {
    cli::cli_abort("{.arg n} must be non-negative for {.fn {unit}}.")
  }
  invisible(n)
}

#' @export
print.il_days <- function(x, ...) {
  cat(format_unit_helper(x), "\n")
  invisible(x)
}

#' @export
print.il_months <- function(x, ...) {
  cat(format_unit_helper(x), "\n")
  invisible(x)
}

#' @export
print.il_years <- function(x, ...) {
  cat(format_unit_helper(x), "\n")
  invisible(x)
}

#' @export
print.il_km <- function(x, ...) {
  cat(format_unit_helper(x), "\n")
  invisible(x)
}

#' @export
print.il_mi <- function(x, ...) {
  cat(format_unit_helper(x), "\n")
  invisible(x)
}

format_unit_helper <- function(x) {
  paste0(x$value, " ", x$unit)
}

#' Extract Numeric Value from a Unit Helper or Bare Numeric
#'
#' @param x A unit helper object or bare numeric.
#' @param expected_unit Optional expected unit string for validation.
#' @return A single numeric value.
#' @noRd
extract_numeric <- function(x, expected_unit = NULL) {
  if (is.numeric(x) && length(x) == 1L) return(x)
  if (is.list(x) && !is.null(x$value) && !is.null(x$unit)) {
    if (!is.null(expected_unit) && x$unit != expected_unit) {
      cli::cli_abort("Expected unit {.val {expected_unit}}, got {.val {x$unit}}.")
    }
    return(x$value)
  }
  cli::cli_abort("Expected a numeric value or unit helper, not {.obj_type_friendly {x}}.")
}

#' Create a Duration in Days
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of days. Inspired by [gt::px()] and [gt::pct()]. Use inside
#' [cl_date_diff()] for self-documenting, unit-safe thresholds.
#'
#' @param n A positive numeric value.
#'
#' @return A tagged numeric with class `il_days`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(days(30), days(365)))
#' }
days <- function(n) {
  check_unit_input(n, "days")
  structure(list(value = n, unit = "days"), class = "il_days")
}

#' Create a Duration in Months
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of months. Use inside [cl_date_diff()] for self-documenting
#' thresholds.
#'
#' @param n A positive numeric value.
#'
#' @return A tagged numeric with class `il_months`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(months(1), months(12)))
#' }
months <- function(n) {
  check_unit_input(n, "months")
  structure(list(value = n, unit = "months"), class = "il_months")
}

#' Create a Duration in Years
#'
#' A tagged-value constructor that marks a numeric threshold as a number
#' of years. Use inside [cl_date_diff()] for self-documenting thresholds.
#'
#' @param n A positive numeric value.
#'
#' @return A tagged numeric with class `il_years`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(dob, cl_date_diff(years(1)))
#' }
years <- function(n) {
  check_unit_input(n, "years")
  structure(list(value = n, unit = "years"), class = "il_years")
}

#' Create a Distance in Kilometres
#'
#' A tagged-value constructor that marks a numeric threshold as a distance
#' in kilometres. Use inside [cl_distance_km()] for self-documenting
#' thresholds.
#'
#' @param n A positive numeric value.
#'
#' @return A tagged numeric with class `il_km`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(lat, lon, cl_distance_km(km(5), km(50)))
#' }
km <- function(n) {
  check_unit_input(n, "km")
  structure(list(value = n, unit = "km"), class = "il_km")
}

#' Create a Distance in Miles
#'
#' A tagged-value constructor that marks a numeric threshold as a distance
#' in miles. Converted to kilometres internally by [cl_distance_km()].
#'
#' @param n A positive numeric value.
#'
#' @return A tagged numeric with class `il_mi`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(lat, lon, cl_distance_km(mi(3), mi(30)))
#' }
mi <- function(n) {
  check_unit_input(n, "mi")
  structure(list(value = n, unit = "mi"), class = "il_mi")
}
