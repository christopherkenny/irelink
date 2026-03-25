#' Levenshtein Edit-Distance Comparison
#'
#' Creates comparison levels based on the Levenshtein edit distance
#' (minimum number of single-character insertions, deletions, or
#' substitutions). Thresholds are integer counts, ordered from strictest
#' (smallest distance) to most lenient.
#'
#' @param ... Integer distance thresholds, ordered from strictest to most
#'   lenient (e.g., `1, 2`).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(name, cl_levenshtein(1, 2))
#' }
cl_levenshtein <- function(...) {
  thresholds <- check_distance_thresholds(c(...), "cl_levenshtein")
  structure(
    list(method = "levenshtein", thresholds = thresholds,
         is_null_level = FALSE, is_else_level = FALSE),
    class = "il_comparison_level"
  )
}

#' Damerau-Levenshtein Edit-Distance Comparison
#'
#' Creates comparison levels based on the Damerau-Levenshtein distance,
#' which extends [cl_levenshtein()] by also counting transpositions of
#' two adjacent characters as a single edit.
#'
#' @param ... Integer distance thresholds, ordered from strictest to most
#'   lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(name, cl_damerau_levenshtein(1))
#' }
cl_damerau_levenshtein <- function(...) {
  thresholds <- check_distance_thresholds(c(...), "cl_damerau_levenshtein")
  structure(
    list(method = "damerau_levenshtein", thresholds = thresholds,
         is_null_level = FALSE, is_else_level = FALSE),
    class = "il_comparison_level"
  )
}
