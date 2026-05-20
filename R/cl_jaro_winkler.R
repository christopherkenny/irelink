#' Jaro-Winkler String Similarity Comparison
#'
#' Creates comparison levels based on the Jaro-Winkler similarity score
#' (0 to 1). Thresholds are passed as unnamed arguments ordered from
#' strictest to most lenient.
#'
#' @param ... Numeric thresholds between 0 and 1, ordered from strictest
#'   to most lenient (e.g., `0.9, 0.7`).
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   value frequency at the highest comparison level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, term_frequency = TRUE))
cl_jaro_winkler <- function(..., term_frequency = FALSE) {
  thresholds <- check_similarity_thresholds(c(...), 'cl_jaro_winkler')
  new_comparison_level(
    'jaro_winkler',
    thresholds = thresholds,
    term_frequency = term_frequency
  )
}

#' Jaro String Similarity Comparison
#'
#' Creates comparison levels based on the Jaro similarity score (0 to 1).
#' A simpler variant of [cl_jaro_winkler()] without the prefix bonus.
#'
#' @param ... Numeric thresholds between 0 and 1, ordered from strictest
#'   to most lenient.
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   value frequency at the highest comparison level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(name, cl_jaro(0.9))
cl_jaro <- function(..., term_frequency = FALSE) {
  thresholds <- check_similarity_thresholds(c(...), 'cl_jaro')
  new_comparison_level(
    'jaro',
    thresholds = thresholds,
    term_frequency = term_frequency
  )
}
