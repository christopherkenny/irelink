#' Compose Custom Comparison Levels
#'
#' Assembles an ordered list of comparison levels from individual level
#' constructors. Use this when the built-in `cl_*()` helpers do not fit
#' and you need full control over the level hierarchy. Analogous to
#' writing a custom [ggplot2::stat_identity()] layer.
#'
#' @param ... Level objects created by [cl_null()], [cl_exact()],
#'   [cl_jaro_winkler()], [cl_else()], and similar helpers.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(
#'     name,
#'     cl_levels(
#'       cl_null(),
#'       cl_exact(term_frequency = TRUE),
#'       cl_jaro_winkler(0.95),
#'       cl_jaro_winkler(0.88),
#'       cl_else()
#'     )
#'   )
cl_levels <- function(...) {
  levels <- list(...)
  if (length(levels) == 0L) {
    cli::cli_abort("{.fn cl_levels} requires at least one level.")
  }
  for (i in seq_along(levels)) {
    if (!inherits(levels[[i]], "il_comparison_level")) {
      cli::cli_abort("All arguments to {.fn cl_levels} must be comparison level objects.")
    }
  }
  # Validate cl_null() is first if present
  null_positions <- which(vapply(levels, function(l) isTRUE(l$is_null_level), logical(1)))
  if (length(null_positions) > 0L && null_positions[1] != 1L) {
    cli::cli_abort(
      "{.fn cl_null} must be the first level in {.fn cl_levels}.",
      class = "il_error_validation"
    )
  }
  # Validate cl_else() is last if present
  else_positions <- which(vapply(levels, function(l) isTRUE(l$is_else_level), logical(1)))
  if (length(else_positions) > 0L && else_positions[length(else_positions)] != length(levels)) {
    cli::cli_abort(
      "{.fn cl_else} must be the last level in {.fn cl_levels}.",
      class = "il_error_validation"
    )
  }
  new_comparison_level("levels", levels = levels)
}

#' Null / Missing Value Level
#'
#' Creates a level that fires when either or both record values are `NULL`
#' or `NA`. Typically used as the first level inside [cl_levels()].
#'
#' @return A comparison-level object.
#' @export
#'
#' @examples
#' cl_levels(cl_null(), cl_exact(), cl_else())
cl_null <- function() {
  new_comparison_level("null", is_null_level = TRUE)
}

#' Catch-All Else Level
#'
#' Creates a residual level that matches any pair not captured by previous
#' levels. Typically used as the last level inside [cl_levels()].
#'
#' @return A comparison-level object.
#' @export
#'
#' @examples
#' cl_levels(cl_null(), cl_exact(), cl_else())
cl_else <- function() {
  new_comparison_level("else", is_else_level = TRUE)
}

#' Combine Comparison Conditions with AND
#'
#' Creates a compound level that fires only when all supplied conditions
#' are satisfied.
#'
#' @param ... Comparison-level objects to AND together.
#'
#' @return A comparison-level object.
#' @export
#'
#' @examples
#' cl_and(cl_exact(), cl_jaro_winkler(0.9))
cl_and <- function(...) {
  children <- list(...)
  if (length(children) == 0L) {
    cli::cli_abort("{.fn cl_and} requires at least one argument.")
  }
  all_null <- all(vapply(children, function(l) isTRUE(l$is_null_level), logical(1)))
  new_comparison_level("and", children = children, is_null_level = all_null)
}

#' Combine Comparison Conditions with OR
#'
#' Creates a compound level that fires when any of the supplied conditions
#' are satisfied.
#'
#' @param ... Comparison-level objects to OR together.
#'
#' @return A comparison-level object.
#' @export
#'
#' @examples
#' cl_or(cl_jaro_winkler(0.9), cl_levenshtein(1))
cl_or <- function(...) {
  children <- list(...)
  if (length(children) == 0L) {
    cli::cli_abort("{.fn cl_or} requires at least one argument.")
  }
  all_null <- all(vapply(children, function(l) isTRUE(l$is_null_level), logical(1)))
  new_comparison_level("or", children = children, is_null_level = all_null)
}

#' Negate a Comparison Condition
#'
#' Creates a level that fires when the supplied condition does **not**
#' hold.
#'
#' @param x A comparison-level object to negate.
#'
#' @return A comparison-level object.
#' @export
#'
#' @examples
#' cl_not(cl_exact())
cl_not <- function(x) {
  if (missing(x)) {
    cli::cli_abort("{.fn cl_not} requires one argument.")
  }
  new_comparison_level("not", child = x)
}
