# S3 class constructors, validators, and type checks.
# These are internal -- users create objects via il_spec(), il_model(), etc.

#' Construct an il_spec Object
#'
#' Low-level constructor for the `il_spec` S3 class. Users should call
#' [il_spec()] instead.
#'
#' @param comparisons A list of comparison layers.
#' @param blocking_rules A list of blocking-rule objects.
#'
#' @return An `il_spec` object.
#' @noRd
new_il_spec <- function(comparisons = list(), blocking_rules = list()) {
  structure(
    list(comparisons = comparisons, blocking_rules = blocking_rules),
    class = 'il_spec'
  )
}

#' Validate an il_spec Object
#'
#' Checks that `x` inherits from `il_spec` and aborts with an
#' informative error if not.
#'
#' @param x An object to validate.
#'
#' @return `x`, invisibly.
#' @noRd
validate_il_spec <- function(x) {
  if (!inherits(x, 'il_spec')) {
    cli::cli_abort('{.arg spec} must be an {.cls il_spec} object.')
  }
  if (!is.list(x) || is.null(x$comparisons) || is.null(x$blocking_rules)) {
    cli::cli_abort(
      '{.cls il_spec} must contain {.field comparisons} and {.field blocking_rules}.'
    )
  }
  invisible(x)
}

#' Construct an il_model Object
#'
#' Low-level constructor for the `il_model` S3 class. Users should call
#' [il_model()] instead.
#'
#' @param spec An `il_spec` object.
#' @param data A list of data frames.
#' @param con A DBI connection or `NULL`.
#' @param link_type A character string.
#' @param params A list of trained parameters.
#' @param trained Logical indicating whether the model has been trained.
#'
#' @return An `il_model` object.
#' @noRd
new_il_model <- function(spec = new_il_spec(), data = list(), con = NULL,
                         link_type = 'dedupe', params = list(),
                         trained = FALSE) {
  structure(
    list(
      spec = spec,
      data = data,
      con = con,
      link_type = link_type,
      params = params,
      trained = trained
    ),
    class = 'il_model'
  )
}

#' Validate an il_model Object
#'
#' Checks that `x` inherits from `il_model` and aborts with an
#' informative error if not.
#'
#' @param x An object to validate.
#'
#' @return `x`, invisibly.
#' @noRd
validate_il_model <- function(x) {
  if (!inherits(x, 'il_model')) {
    cli::cli_abort('{.arg model} must be an {.cls il_model} object.')
  }
  invisible(x)
}

#' Construct an il_compared Object
#'
#' Low-level constructor for the `il_compared` S3 class (a tibble
#' subclass). Users receive these from [predict.il_model()].
#'
#' @param x A tibble of scored record pairs.
#' @param model The `il_model` that produced the comparisons, or `NULL`.
#'
#' @return An `il_compared` tibble.
#' @noRd
new_il_compared <- function(x = tibble::tibble(), model = NULL) {
  if (!inherits(x, 'tbl_df')) {
    cli::cli_abort('{.arg x} must be a tibble.')
  }
  structure(x, class = c('il_compared', class(x)), model = model)
}

#' Validate an il_compared Object
#'
#' Checks that `x` inherits from `il_compared` and aborts with an
#' informative error if not.
#'
#' @param x An object to validate.
#'
#' @return `x`, invisibly.
#' @noRd
validate_il_compared <- function(x) {
  if (!inherits(x, 'il_compared')) {
    cli::cli_abort('{.arg pairs} must be an {.cls il_compared} object.')
  }
  invisible(x)
}

#' Construct an il_comparison_level Object
#'
#' Shared constructor used by all `cl_*()` helpers to avoid repeating the
#' `structure(list(..., is_null_level = FALSE, is_else_level = FALSE),
#' class = "il_comparison_level")` boilerplate.
#'
#' @param method Character string naming the comparison method.
#' @param ... Additional named fields stored in the level (e.g., `thresholds`).
#' @param is_null_level Logical; TRUE for null sentinel levels.
#' @param is_else_level Logical; TRUE for else fallback levels.
#'
#' @return An `il_comparison_level` S3 object.
#' @noRd
new_comparison_level <- function(method, ..., is_null_level = FALSE,
                                 is_else_level = FALSE) {
  structure(
    c(
      list(method = method), list(...),
      list(is_null_level = is_null_level, is_else_level = is_else_level)
    ),
    class = 'il_comparison_level'
  )
}

#' Prepend a class to a tibble
#'
#' Adds a custom S3 class in front of the existing class vector so that
#' methods like `autoplot()` can dispatch on it while preserving the
#' underlying tibble behaviour.
#'
#' @param x A tibble.
#' @param cls Character string. The class name to prepend.
#'
#' @return `x` with `cls` prepended to its class vector.
#' @noRd
add_class <- function(x, cls) {
  class(x) <- c(cls, class(x))
  x
}
