#' Numeric Absolute Difference Comparison
#'
#' Creates comparison levels based on the absolute difference between two
#' numeric values. Thresholds are ordered from strictest (smallest
#' permitted difference) to most lenient.
#'
#' @param ... Numeric difference thresholds, ordered from strictest to
#'   most lenient (e.g., `1, 5`).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(age, cl_numeric_diff(1, 5))
#' }
cl_numeric_diff <- function(...) {
  thresholds <- check_distance_thresholds(c(...), "cl_numeric_diff")
  new_comparison_level("numeric_diff", thresholds = thresholds)
}

#' Numeric Percentage Difference Comparison
#'
#' Creates comparison levels based on the relative percentage difference
#' between two numeric values. Thresholds are fractions (e.g., `0.05`
#' for 5%), ordered from strictest to most lenient.
#'
#' @param ... Numeric percentage thresholds, ordered from strictest to
#'   most lenient (e.g., `0.05, 0.2`).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(income, cl_pct_diff(0.05, 0.2))
#' }
cl_pct_diff <- function(...) {
  thresholds <- check_distance_thresholds(c(...), "cl_pct_diff")
  new_comparison_level("pct_diff", thresholds = thresholds)
}
