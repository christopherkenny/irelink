# Unit helpers ─ tagged-value constructors for self-documenting thresholds.
# Inspired by gt's px(), pct(), and md().
#
# NOTE: days(), months(), and years() share names with lubridate exports.
# We accept the namespace collision because:
#   1. irelink's versions are tagged-value constructors, not durations.
#   2. Users will rarely load both irelink and lubridate simultaneously.
#   3. Explicit namespacing (irelink::days()) resolves any ambiguity.

#' @export
days <- function(n) {
  cli::cli_warn("Function {.fn days} is not yet implemented.")
  invisible(NULL)
}

#' @export
months <- function(n) {
  cli::cli_warn("Function {.fn months} is not yet implemented.")
  invisible(NULL)
}

#' @export
years <- function(n) {
  cli::cli_warn("Function {.fn years} is not yet implemented.")
  invisible(NULL)
}

#' @export
km <- function(n) {
  cli::cli_warn("Function {.fn km} is not yet implemented.")
  invisible(NULL)
}

#' @export
mi <- function(n) {
  cli::cli_warn("Function {.fn mi} is not yet implemented.")
  invisible(NULL)
}
