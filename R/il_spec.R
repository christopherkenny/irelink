#' @export
il_spec <- function() {
  cli::cli_warn("Function {.fn il_spec} is not yet implemented.")
  invisible(NULL)
}

#' @export
print.il_spec <- function(x, ...) {
  cli::cli_warn("Function {.fn print.il_spec} is not yet implemented.")
  invisible(x)
}

#' @export
is_il_spec <- function(x) {
  inherits(x, "il_spec")
}
