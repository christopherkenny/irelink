#' Jaccard Set Similarity Comparison
#'
#' Creates comparison levels based on the Jaccard index, the ratio of the
#' intersection to the union of character n-gram sets. Thresholds are
#' between 0 and 1, ordered from strictest to most lenient.
#'
#' @param ... Numeric thresholds between 0 and 1, ordered from strictest
#'   to most lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(name, cl_jaccard(0.9))
#' }
cl_jaccard <- function(...) {
  cli::cli_warn("Function {.fn cl_jaccard} is not yet implemented.")
  invisible(NULL)
}
