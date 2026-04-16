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
#' @param transform An optional transformation function applied to both
#'   left and right column values *before* comparison. Common choices
#'   include `tolower`, `toupper`, and `trimws`, which are automatically
#'   translated to SQL when a database backend is available. Custom
#'   functions work on the R-side path only.
#' @param tf_adjustment_weight Numeric power to raise the term-frequency
#'   Bayes factor to. A value of `1.0` (the default) applies the full
#'   adjustment; `0` disables it entirely. Only relevant when the
#'   comparison method has `term_frequency = TRUE`.
#' @param tf_minimum_u_value Numeric floor for the term-frequency
#'   denominator. When both TF values are below this threshold, it is
#'   used instead — preventing unrealistically large match weights for
#'   very rare terms. Defaults to `0.0` (no floor).
#' @param ... Reserved for future use.
#'
#' @return An updated `il_spec` (a new copy; the input is not modified).
#' @export
#'
#' @examples
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_date_diff(days(30), days(365)))
#'
#' # Apply a transform before comparing
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7), transform = tolower)
#'
#' # Scale TF adjustment weight
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, term_frequency = TRUE),
#'     tf_adjustment_weight = 0.5, tf_minimum_u_value = 0.001
#'   )
il_compare <- function(spec, col, method, ...,
                       transform = NULL,
                       tf_adjustment_weight = 1.0,
                       tf_minimum_u_value = 0.0) {
  if (!inherits(spec, 'il_spec')) {
    cli::cli_abort(
      '{.arg spec} must be an {.cls il_spec} object, not {.obj_type_friendly {spec}}.',
      class = 'il_error_type'
    )
  }
  if (!is.null(transform) && !is.function(transform)) {
    cli::cli_abort(
      '{.arg transform} must be a function or {.code NULL}, not {.obj_type_friendly {transform}}.',
      class = 'il_error_type'
    )
  }
  col_expr <- rlang::enquo(col)
  columns <- extract_col_names(col_expr)
  for (column in columns) {
    entry <- list(
      columns = column, method = method, transform = transform,
      tf_adjustment_weight = tf_adjustment_weight,
      tf_minimum_u_value = tf_minimum_u_value
    )
    spec$comparisons <- c(spec$comparisons, list(entry))
  }
  spec
}

# Extract column names from a quosure. Handles bare names, c(), and
# tidyselect helpers (which are stored as deferred expressions).
extract_col_names <- function(quo) {
  expr <- rlang::quo_get_expr(quo)
  if (rlang::is_symbol(expr)) {
    return(as.character(expr))
  }
  if (rlang::is_call(expr, 'c')) {
    args <- as.list(expr)[-1]
    return(vapply(args, function(a) {
      if (rlang::is_symbol(a)) {
        as.character(a)
      } else {
        deparse(a)
      }
    }, character(1)))
  }
  # Tidyselect helpers (starts_with, everything, matches, etc.) —
  # store as deferred expression string
  list(deparse(expr))
}
