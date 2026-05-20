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
#' il_spec() |>
#'   il_compare(c(lat, lon), cl_geo_distance(km(5), km(50)))
#'
#' # Use miles instead
#' il_spec() |>
#'   il_compare(c(lat, lon), cl_geo_distance(mi(3), mi(30)))
cl_geo_distance <- function(...) {
  args <- list(...)
  if (length(args) == 0L) {
    cli::cli_abort('{.fn cl_geo_distance} requires at least one threshold.')
  }
  mi_to_km <- 1.609344
  thresholds <- vapply(
    args,
    function(a) {
      if (is.numeric(a) && length(a) == 1L) {
        check_unit_input(a, 'cl_geo_distance')
        return(a)
      }
      if (is.list(a) && !is.null(a$unit)) {
        if (a$unit == 'km') {
          return(a$value)
        }
        if (a$unit == 'mi') {
          return(a$value * mi_to_km)
        }
        cli::cli_abort(
          '{.fn cl_geo_distance} accepts {.val km} or {.val mi} units, not {.val {a$unit}}.'
        )
      }
      cli::cli_abort('Invalid threshold for {.fn cl_geo_distance}.')
    },
    numeric(1)
  )
  if (length(thresholds) > 1L && is.unsorted(thresholds)) {
    cli::cli_warn(
      'Thresholds for {.fn cl_geo_distance} should be in ascending order; re-ordering.'
    )
    thresholds <- sort(thresholds)
  }
  new_comparison_level('geo_distance', thresholds = thresholds)
}
