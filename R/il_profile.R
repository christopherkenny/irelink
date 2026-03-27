#' Profile Column Value Distributions
#'
#' Computes summary statistics and value-frequency distributions for
#' selected columns of a data frame. Useful for understanding data quality
#' before defining comparison rules.
#'
#' @param .data A data frame or tibble to profile.
#' @param ... <[`tidy-select`][dplyr::dplyr_tidy_select]> Columns to
#'   profile. If empty, all columns are profiled.
#' @param con A DBI connection object used for computation.
#'
#' @return A tibble of per-column summary statistics.
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
#' il_profile(df, first_name, surname, con = con)
#' DBI::dbDisconnect(con)
il_profile <- function(.data, ..., con) {
  col_exprs <- rlang::enquos(...)
  col_names <- vapply(col_exprs, function(q) {
    as.character(rlang::quo_get_expr(q))
  }, character(1))

  if (length(col_names) == 0L) {
    col_names <- names(.data)
  }

  tbl_name <- "__il_profile_tmp"
  DBI::dbWriteTable(con, tbl_name, .data, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, tbl_name, fail_if_missing = FALSE), add = TRUE)

  results <- lapply(col_names, function(col_nm) {
    quoted_col <- DBI::dbQuoteIdentifier(con, col_nm)
    quoted_tbl <- DBI::dbQuoteIdentifier(con, tbl_name)
    sql <- glue::glue(
      "SELECT {quoted_col} AS value, COUNT(*) AS n FROM {quoted_tbl} ",
      "GROUP BY {quoted_col} ORDER BY n DESC"
    )
    res <- DBI::dbGetQuery(con, sql)
    res$column <- col_nm
    tibble::as_tibble(res[, c("column", "value", "n")])
  })

  do.call(rbind, results)
}
