#' Jaro-Winkler String Similarity Comparison
#'
#' Creates comparison levels based on the Jaro-Winkler similarity score
#' (0 to 1). Thresholds are passed as unnamed arguments ordered from
#' strictest to most lenient — the same direction you would read them in
#' a waterfall chart.
#'
#' @param ... Numeric thresholds between 0 and 1, ordered from strictest
#'   to most lenient (e.g., `0.9, 0.7`).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' \dontrun{
#' il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9))
#' }
cl_jaro_winkler <- function(...) {
  cli::cli_warn("Function {.fn cl_jaro_winkler} is not yet implemented.")
  invisible(NULL)
}

#' Jaro String Similarity Comparison
#'
#' Creates comparison levels based on the Jaro similarity score (0 to 1).
#' A simpler variant of [cl_jaro_winkler()] without the prefix bonus.
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
#'   il_compare(name, cl_jaro(0.9))
#' }
cl_jaro <- function(...) {
  cli::cli_warn("Function {.fn cl_jaro} is not yet implemented.")
  invisible(NULL)
}
