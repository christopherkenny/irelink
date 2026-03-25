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
  validate_il_spec(spec)
  comparisons <- spec$comparisons

  a <- as.data.frame(record_a, stringsAsFactors = FALSE)
  b <- as.data.frame(record_b, stringsAsFactors = FALSE)

  pair <- as.data.frame(c(
    stats::setNames(as.list(a[1, , drop = FALSE]), paste0("l_", names(a))),
    stats::setNames(as.list(b[1, , drop = FALSE]), paste0("r_", names(b)))
  ))

  gamma_mat <- compute_gamma_matrix(pair, comparisons)
  comp_names <- colnames(gamma_mat)

  result <- tibble::tibble(.rows = 1L)
  for (j in seq_along(comp_names)) {
    result[[paste0("gamma_", comp_names[j])]] <- gamma_mat[1, j]
  }
  result
}
