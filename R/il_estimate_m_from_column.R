#' Estimate Match (m) Parameters from a Label Column
#'
#' Learns the m probabilities from a ground-truth identifier column
#' (e.g., Social Security Number) present in the input data. Records
#' sharing the same label value are treated as true matches. This is an
#' alternative to [il_estimate_m_from_labels()], which requires a
#' separate table of pairwise labels.
#'
#' @param model An `il_model` object (piped in).
#' @param label_col The unquoted name of a column in the input data
#'   containing ground-truth entity identifiers.
#'
#' @return An updated `il_model` with estimated m parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u() |>
#'   il_estimate_m_from_column(true_person_id)
#' }
il_estimate_m_from_column <- function(model, label_col) {
  cli::cli_warn("Function {.fn il_estimate_m_from_column} is not yet implemented.")
  invisible(NULL)
}
