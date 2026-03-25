#' Create an Empty Linkage Specification
#'
#' Initialises a blank `il_spec` object onto which comparison layers and
#' blocking rules are added with [il_compare()] and [il_block_on()].
#' Analogous to [ggplot2::ggplot()] creating an empty canvas.
#'
#' @return An `il_spec` object with no comparisons or blocking rules.
#' @export
#'
#' @examples
#' \dontrun{
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
#' }
il_spec <- function() {
  cli::cli_warn("Function {.fn il_spec} is not yet implemented.")
  invisible(NULL)
}

#' Print an irelink Specification
#'
#' Displays a human-readable summary of the comparisons and blocking rules
#' stored in an `il_spec` object.
#'
#' @param x An `il_spec` object.
#' @param ... Additional arguments passed to [print()].
#'
#' @return `x`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_exact())
#' print(spec)
#' }
print.il_spec <- function(x, ...) {
  cli::cli_warn("Function {.fn print.il_spec} is not yet implemented.")
  invisible(x)
}

#' Test if an Object is an irelink Specification
#'
#' Returns `TRUE` if `x` inherits from class `il_spec`.
#'
#' @param x An object to test.
#'
#' @return A single logical value.
#' @export
#'
#' @examples
#' \dontrun{
#' is_il_spec(il_spec())
#' }
is_il_spec <- function(x) {
  inherits(x, "il_spec")
}
