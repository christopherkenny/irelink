#' Geographic Distance Comparison
#'
#' Creates comparison levels based on the great-circle distance between
#' two latitude/longitude pairs. Thresholds should use the unit helpers
#' [km()] or [mi()] for clarity.
#'
#' @param ... Distance thresholds created by [km()] or [mi()], ordered
#'   from strictest to most lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(lat, lon, cl_distance_km(km(5), km(50)))
#'
#' # Use miles instead
#' il_spec() |>
#'   il_compare(lat, lon, cl_distance_km(mi(3), mi(30)))
#' }
cl_distance_km <- function(...) {
  cli::cli_warn("Function {.fn cl_distance_km} is not yet implemented.")
  invisible(NULL)
}
