#' Cosine Similarity Comparison
#'
#' Creates comparison levels based on cosine similarity. Suitable for
#' numeric or vectorised columns. Thresholds are between 0 and 1, ordered
#' from strictest to most lenient.
#'
#' @param ... Numeric thresholds between 0 and 1, ordered from strictest
#'   to most lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(embedding, cl_cosine(0.8))
cl_cosine <- function(...) {
  thresholds <- check_similarity_thresholds(c(...), 'cl_cosine')
  new_comparison_level('cosine', thresholds = thresholds)
}
