# Unit helpers -- tagged-value constructors for self-documenting thresholds.
# Inspired by gt's px(), pct(), and md().
#
# NOTE: days(), months(), and years() share names with lubridate exports.
# We accept the namespace collision because:
#   1. irelink's versions are tagged-value constructors, not durations.
#   2. Users will rarely load both irelink and lubridate simultaneously.
#   3. Explicit namespacing (irelink::days()) resolves any ambiguity.

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
  cli::cli_warn("Function {.fn days} is not yet implemented.")
  invisible(NULL)
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
  cli::cli_warn("Function {.fn months} is not yet implemented.")
  invisible(NULL)
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
  cli::cli_warn("Function {.fn years} is not yet implemented.")
  invisible(NULL)
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
  cli::cli_warn("Function {.fn km} is not yet implemented.")
  invisible(NULL)
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
  cli::cli_warn("Function {.fn mi} is not yet implemented.")
  invisible(NULL)
}
