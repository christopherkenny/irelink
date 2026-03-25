#' Add a Comparison Layer to a Specification
#'
#' Declares how one or more columns should be compared when scoring record
#' pairs. Each call accumulates a new layer onto the spec, following the
#' same stacking pattern as [ggplot2::geom_point()] layers.
#'
#' `col` accepts tidyselect expressions: a bare column name, `c(col_a,
#' col_b)`, or helpers such as [tidyselect::starts_with()]. When multiple
#' columns are targeted, each receives its own comparison layer with the
#' same method, mirroring [gt::fmt_number()]'s `columns` argument.
#'
#' @param spec An `il_spec` object (piped in).
#' @param col <[`tidy-select`][dplyr::dplyr_tidy_select]> Column(s) to
#'   compare. Accepts bare names, `c()`, and tidyselect helpers.
#' @param method A comparison helper object created by a `cl_*()` function
#'   such as [cl_exact()] or [cl_jaro_winkler()].
#' @param ... Reserved for future use.
#'
#' @return An updated `il_spec` (a new copy; the input is not modified).
#' @export
#'
#' @examples
#' \dontrun{
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_date_diff(days(30), days(365)))
#'
#' # Target multiple columns with the same method
#' spec <- il_spec() |>
#'   il_compare(c(first_name, last_name), cl_jaro_winkler(0.9, 0.7))
#' }
il_compare <- function(spec, col, method, ...) {
  cli::cli_warn("Function {.fn il_compare} is not yet implemented.")
  invisible(NULL)
}
