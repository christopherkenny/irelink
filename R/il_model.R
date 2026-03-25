#' @export
il_model <- function(.data, ..., spec, con,
                     link_type = c("dedupe", "link", "link_and_dedupe")) {
  cli::cli_warn("Function {.fn il_model} is not yet implemented.")
  invisible(NULL)
}

#' @export
print.il_model <- function(x, ...) {
  cli::cli_warn("Function {.fn print.il_model} is not yet implemented.")
  invisible(x)
}

#' @export
summary.il_model <- function(object, ...) {
  cli::cli_warn("Function {.fn summary.il_model} is not yet implemented.")
  invisible(NULL)
}

#' @export
is_il_model <- function(x) {
  inherits(x, "il_model")
}
