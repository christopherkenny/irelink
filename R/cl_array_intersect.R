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
#' il_spec() |>
#'   il_compare(tags, cl_array_intersect(2, 1))
cl_array_intersect <- function(...) {
  thresholds <- check_distance_thresholds(c(...), 'cl_array_intersect')
  new_comparison_level('array_intersect', thresholds = thresholds)
}

#' Array Subset Comparison
#'
#' Creates a comparison level that matches when the smaller of two array
#' columns is a complete subset of the larger — i.e., every element of
#' the smaller array appears in the larger one. Equivalent to splink's
#' `ArraySubsetLevel`.
#'
#' On DuckDB and PostgreSQL this is computed in SQL using
#' `ARRAY_LENGTH(ARRAY_INTERSECT(...)) = LEAST(ARRAY_LENGTH(...))`.
#' On SQLite it falls back to an R-side set check.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(qualifications, cl_array_subset())
cl_array_subset <- function() {
  new_comparison_level('array_subset')
}
