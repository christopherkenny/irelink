# Shared validation helpers for cl_* comparison level constructors.

#' Construct an il_comparison_level Object
#'
#' Shared constructor used by all `cl_*()` helpers to avoid repeating the
#' `structure(list(..., is_null_level = FALSE, is_else_level = FALSE),
#' class = "il_comparison_level")` boilerplate.
#'
#' @param method Character string naming the comparison method.
#' @param ... Additional named fields stored in the level (e.g., `thresholds`).
#' @param is_null_level Logical. TRUE for null sentinel levels.
#' @param is_else_level Logical. TRUE for else fallback levels.
#'
#' @return An `il_comparison_level` S3 object.
#' @noRd
new_comparison_level <- function(
  method,
  ...,
  is_null_level = FALSE,
  is_else_level = FALSE
) {
  structure(
    c(
      list(method = method),
      list(...),
      list(is_null_level = is_null_level, is_else_level = is_else_level)
    ),
    class = 'il_comparison_level'
  )
}

#' Count the number of gamma levels a comparison produces
#'
#' Binary comparisons (cl_exact, single-threshold fuzzy) produce 2 levels.
#' Multi-threshold comparisons produce `length(thresholds) + 1` levels.
#' Composite comparisons (cl_levels) count non-null, non-else sublevels + 1.
#'
#' @param comp_method An il_comparison_level object (the `$method` element).
#' @return Integer: the number of gamma levels (always >= 2).
#' @noRd
n_gamma_levels <- function(comp_method) {
  method <- comp_method$method

  if (method == 'exact') {
    return(2L)
  }

  if (!is.null(comp_method$thresholds)) {
    return(length(comp_method$thresholds) + 1L)
  }

  if (method == 'levels') {
    n <- sum(vapply(
      comp_method$levels,
      function(l) {
        !isTRUE(l$is_null_level) && !isTRUE(l$is_else_level)
      },
      logical(1)
    ))
    return(max(n + 1L, 2L))
  }

  2L
}

#' Validate similarity thresholds (must be between 0 and 1, descending)
#' @param thresholds Numeric vector of thresholds.
#' @param fn_name Name of the calling function (for error messages).
#' @return The (potentially re-ordered) thresholds.
#' @noRd
check_similarity_thresholds <- function(thresholds, fn_name) {
  if (length(thresholds) == 0L) {
    cli::cli_abort('{.fn {fn_name}} requires at least one threshold.')
  }
  if (!is.numeric(thresholds) || anyNA(thresholds)) {
    cli::cli_abort('Thresholds for {.fn {fn_name}} must be numeric.')
  }
  if (any(thresholds < 0 | thresholds > 1)) {
    cli::cli_abort('Thresholds for {.fn {fn_name}} must be between 0 and 1.')
  }
  if (length(thresholds) > 1L && is.unsorted(rev(thresholds))) {
    cli::cli_warn(
      'Thresholds for {.fn {fn_name}} should be in descending order; re-ordering.'
    )
    thresholds <- sort(thresholds, decreasing = TRUE)
  }
  thresholds
}

#' Validate distance/count thresholds (must be non-negative)
#' @param thresholds Numeric vector of thresholds.
#' @param fn_name Name of the calling function (for error messages).
#' @return The thresholds.
#' @noRd
check_distance_thresholds <- function(thresholds, fn_name) {
  if (length(thresholds) == 0L) {
    cli::cli_abort('{.fn {fn_name}} requires at least one threshold.')
  }
  if (!is.numeric(thresholds) || anyNA(thresholds)) {
    cli::cli_abort('Thresholds for {.fn {fn_name}} must be numeric.')
  }
  if (any(thresholds < 0)) {
    cli::cli_abort('Thresholds for {.fn {fn_name}} must be non-negative.')
  }
  if (length(thresholds) > 1L && is.unsorted(thresholds)) {
    cli::cli_warn(
      'Thresholds for {.fn {fn_name}} should be in ascending order; re-ordering.'
    )
    thresholds <- sort(thresholds)
  }
  thresholds
}
