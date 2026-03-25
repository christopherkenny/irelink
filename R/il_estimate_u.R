#' Estimate Non-Match (u) Parameters
#'
#' Estimates the u probabilities (the probability of observing each
#' comparison level given that the records do **not** match) by randomly
#' sampling record pairs. Most random pairs are non-matches, so the
#' observed level frequencies approximate the u distribution.
#'
#' @param model An `il_model` object (piped in).
#' @param max_pairs Maximum number of random pairs to sample. Defaults to
#'   `1e6`.
#'
#' @return An updated `il_model` with estimated u parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u(max_pairs = 1e6)
#' }
il_estimate_u <- function(model, max_pairs = 1e6) {
  cli::cli_warn("Function {.fn il_estimate_u} is not yet implemented.")
  invisible(NULL)
}
