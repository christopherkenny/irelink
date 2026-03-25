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
  thresholds <- check_similarity_thresholds(c(...), "cl_jaccard")
  structure(
    list(method = "jaccard", thresholds = thresholds,
         is_null_level = FALSE, is_else_level = FALSE),
    class = "il_comparison_level"
  )
}
