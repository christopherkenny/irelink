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
#' \dontrun{
#' # Block on state OR first name (two calls = OR)
#' spec <- il_spec() |>
#'   il_block_on(state) |>
#'   il_block_on(first_name)
#'
#' # Block where state AND year both match (one call = AND)
#' spec <- il_spec() |>
#'   il_block_on(state, year)
#' }
il_block_on <- function(spec, ..., .where = NULL) {
  cli::cli_warn("Function {.fn il_block_on} is not yet implemented.")
  invisible(NULL)
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
#'
#' @return A blocking-rule object for use in training verbs.
#' @export
#'
#' @examples
#' \dontrun{
#' model |>
#'   il_estimate_em(block_on(first_name, surname))
#' }
block_on <- function(...) {
  cli::cli_warn("Function {.fn block_on} is not yet implemented.")
  invisible(NULL)
}
