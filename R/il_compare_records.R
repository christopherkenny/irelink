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
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c("John", "Jon", "Jane", "Jane", "Bob",
#'                   "Bobby", "Alice", "Alicia", "Tom", "Thomas",
#'                   "John", "Jon", "Jane", "Janet", "Bob",
#'                   "Robert", "Alice", "Alison", "Tom", "Tomas"),
#'   surname = c("Smith", "Smith", "Doe", "Doe", "Jones",
#'               "Jones", "Brown", "Brown", "White", "White",
#'               "Smith", "Smyth", "Doe", "Doe", "Jones",
#'               "Jones", "Brown", "Browne", "White", "White"),
#'   dob = c("1990-01-01", "1990-01-01", "1985-06-15", "1985-06-15",
#'           "2000-12-01", "2000-12-01", "1975-03-22", "1975-03-22",
#'           "1988-07-04", "1988-07-04", "1990-01-01", "1990-01-02",
#'           "1985-06-15", "1985-06-16", "2000-12-01", "2000-12-02",
#'           "1975-03-22", "1975-03-23", "1988-07-04", "1988-07-05"),
#'   city = c("London", "London", "Paris", "Paris", "Berlin",
#'            "Berlin", "Rome", "Rome", "Madrid", "Madrid",
#'            "London", "London", "Paris", "Paris", "Berlin",
#'            "Berlin", "Rome", "Rome", "Madrid", "Madrid"),
#'   email = c("john@example.com", "jon@example.com", "jane@example.com",
#'             "jane@example.com", "bob@example.com", "bobby@example.com",
#'             "alice@example.com", "alicia@example.com", "tom@example.com",
#'             "thomas@example.com", "john@example.com", "jon@example.com",
#'             "jane@example.com", "janet@example.com", "bob@example.com",
#'             "robert@example.com", "alice@example.com", "alison@example.com",
#'             "tom@example.com", "tomas@example.com")
#' )
#' con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' record_a <- df[1, ]
#' record_b <- df[2, ]
#'
#' il_compare_records(record_a, record_b, spec = spec, con = con)
#' DBI::dbDisconnect(con)
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
