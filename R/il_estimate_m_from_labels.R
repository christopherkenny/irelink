#' Estimate Match (m) Parameters from Labelled Data
#'
#' Learns the m probabilities (the probability of observing each
#' comparison level given that the records **do** match) from a set of
#' pre-labelled record pairs. Use this instead of [il_estimate_em()] when
#' ground-truth labels are available.
#'
#' @param model An `il_model` object (piped in).
#' @param labels A data frame of labelled pairs with columns identifying
#'   the left record, right record, and a logical or integer match
#'   indicator.
#'
#' @return An updated `il_model` with estimated m parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u() |>
#'   il_estimate_m_from_labels(labelled_pairs)
#' }
il_estimate_m_from_labels <- function(model, labels) {
  cli::cli_warn("Function {.fn il_estimate_m_from_labels} is not yet implemented.")
  invisible(NULL)
}
