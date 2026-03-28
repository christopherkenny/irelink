#' Add a Prediction Blocking Rule
#'
#' Adds an equality-based blocking rule to a specification. During
#' prediction, only record pairs that agree on the blocking columns are
#' scored. Multiple calls are OR-ed together; within a single call,
#' columns are AND-ed. This mirrors [dplyr::join_by()] where multiple
#' conditions inside one call are AND-ed.
#'
#' @param spec An `il_spec` object (piped in).
#' @param ... <[`tidy-select`][dplyr::dplyr_tidy_select]> Columns for
#'   equality blocking (AND-ed within one call).
#' @param .where An optional raw SQL string for non-equality blocking
#'   conditions. Defaults to `NULL`.
#'
#' @return An updated `il_spec` (a new copy; the input is not modified).
#' @export
#'
#' @examples
#' # Block on state OR first name (two calls = OR)
#' spec <- il_spec() |>
#'   il_block_on(state) |>
#'   il_block_on(first_name)
#'
#' # Block where state AND year both match (one call = AND)
#' spec <- il_spec() |>
#'   il_block_on(state, year)
il_block_on <- function(spec, ..., .where = NULL) {
  if (!inherits(spec, 'il_spec')) {
    cli::cli_abort(
      '{.arg spec} must be an {.cls il_spec} object, not {.obj_type_friendly {spec}}.',
      class = 'il_error_type'
    )
  }
  col_exprs <- rlang::enquos(...)
  columns <- vapply(col_exprs, function(q) {
    expr <- rlang::quo_get_expr(q)
    if (rlang::is_symbol(expr)) {
      as.character(expr)
    } else {
      deparse(expr)
    }
  }, character(1))
  rule <- structure(
    list(columns = columns, where = .where),
    class = 'il_blocking_rule'
  )
  spec$blocking_rules <- c(spec$blocking_rules, list(rule))
  spec
}

#' Create a Training-Time Blocking Rule
#'
#' Creates a blocking rule for use inside training verbs such as
#' [il_estimate_em()] and [il_estimate_prior()]. This is distinct from
#' [il_block_on()], which adds prediction-time blocking to a specification.
#' Analogous to [dplyr::join_by()] — a specification object that describes
#' how to partition pairs during training.
#'
#' @param ... Unquoted column names. Columns are AND-ed within a single
#'   `block_on()` call.
#' @param .where An optional raw SQL string for non-equality blocking
#'   conditions (e.g., `"levenshtein(l.dob, r.dob) <= 1"`). When
#'   supplied alongside column names, the column equalities and the SQL
#'   condition are AND-ed together.
#'
#' @return A blocking-rule object for use in training verbs.
#' @export
#'
#' @examples
#' block_on(first_name, surname)
#'
#' # Fuzzy SQL conditions
#' block_on(first_name, .where = 'levenshtein(l.dob, r.dob) <= 1')
block_on <- function(..., .where = NULL) {
  col_exprs <- rlang::enquos(...)
  if (length(col_exprs) == 0L && is.null(.where)) {
    cli::cli_abort('{.fn block_on} requires at least one column or a {.arg .where} condition.')
  }
  columns <- vapply(col_exprs, function(q) {
    expr <- rlang::quo_get_expr(q)
    if (rlang::is_symbol(expr)) {
      as.character(expr)
    } else {
      deparse(expr)
    }
  }, character(1))
  structure(
    list(columns = columns, where = .where),
    class = 'il_blocking_rule'
  )
}
