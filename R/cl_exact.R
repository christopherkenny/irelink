#' Exact Equality Comparison
#'
#' Creates a comparison level that scores an exact match on a column.
#' Optionally applies term-frequency adjustments so that rare values
#' (e.g., an uncommon surname) receive higher match weights than common
#' ones.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   value frequency. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(city, cl_exact()) |>
#'   il_compare(county, cl_exact(term_frequency = TRUE))
#' }
cl_exact <- function(term_frequency = FALSE) {
  new_comparison_level("exact", term_frequency = term_frequency)
}
