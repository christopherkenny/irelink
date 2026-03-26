#' Array Intersection Comparison
#'
#' Creates comparison levels based on the number of shared elements
#' between two array or list columns. Thresholds are integer counts,
#' ordered from strictest (most shared elements required) to most lenient.
#'
#' @param ... Integer count thresholds, ordered from strictest to most
#'   lenient (e.g., `2, 1`).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(tags, cl_array_intersect(2, 1))
#' }
cl_array_intersect <- function(...) {
  thresholds <- check_distance_thresholds(c(...), "cl_array_intersect")
  new_comparison_level("array_intersect", thresholds = thresholds)
}
