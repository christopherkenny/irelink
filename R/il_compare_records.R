#' Compare Two Individual Records
#'
#' Scores a single pair of records against a specification without
#' requiring a full training pipeline. Useful for quick one-off
#' comparisons or debugging.
#'
#' @param record_a A named list or single-row data frame representing the
#'   first record.
#' @param record_b A named list or single-row data frame representing the
#'   second record.
#' @param spec An `il_spec` object describing the comparisons to perform.
#' @param con A DBI connection object.
#'
#' @return A single-row tibble with match weight, match probability, and
#'   per-comparison gamma values.
#' @export
#'
#' @examples
#' \dontrun{
#' il_compare_records(
#'   list(first_name = "John", surname = "Smith", dob = "1985-01-15"),
#'   list(first_name = "Jon",  surname = "Smith", dob = "1985-02-15"),
#'   spec = spec,
#'   con = con
#' )
#' }
il_compare_records <- function(record_a, record_b, spec, con) {
  cli::cli_warn("Function {.fn il_compare_records} is not yet implemented.")
  invisible(NULL)
}
