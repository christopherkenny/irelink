# Shared validation helpers for cl_* comparison level constructors.

#' Validate similarity thresholds (must be between 0 and 1, descending)
#' @param thresholds Numeric vector of thresholds.
#' @param fn_name Name of the calling function (for error messages).
#' @return The (potentially re-ordered) thresholds.
#' @noRd
check_similarity_thresholds <- function(thresholds, fn_name) {
  if (length(thresholds) == 0L) {
    cli::cli_abort('{.fn {fn_name}} requires at least one threshold.')
  }
  if (!is.numeric(thresholds) || any(is.na(thresholds))) {
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
  if (!is.numeric(thresholds) || any(is.na(thresholds))) {
    cli::cli_abort('Thresholds for {.fn {fn_name}} must be numeric.')
  }
  if (any(thresholds < 0)) {
    cli::cli_abort('Thresholds for {.fn {fn_name}} must be non-negative.')
  }
  thresholds
}
