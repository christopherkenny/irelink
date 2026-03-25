#' Train Parameters via Expectation-Maximisation
#'
#' Runs the EM algorithm under a blocking rule to learn m and u parameters
#' from unlabelled data. Multiple calls with different blocking rules can
#' be chained to train on complementary subsets of record pairs — each
#' call updates the model cumulatively. Analogous to [parsnip::fit()] in
#' tidymodels.
#'
#' @param model An `il_model` object (piped in).
#' @param blocking A blocking rule created by [block_on()].
#' @param ... Reserved for future options (e.g., convergence tolerance,
#'   maximum iterations).
#'
#' @return An updated `il_model` with trained m and u parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u() |>
#'   il_estimate_em(block_on(first_name, surname)) |>
#'   il_estimate_em(block_on(dob))
#' }
il_estimate_em <- function(model, blocking, ...) {
  cli::cli_warn("Function {.fn il_estimate_em} is not yet implemented.")
  invisible(NULL)
}
