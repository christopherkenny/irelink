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
#' \dontrun{
#' il_profile(voters, first_name, surname, dob, con = con)
#' }
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
    sql <- sprintf(
      "SELECT %s AS value, COUNT(*) AS n FROM %s GROUP BY %s ORDER BY n DESC",
      DBI::dbQuoteIdentifier(con, col_nm),
      DBI::dbQuoteIdentifier(con, tbl_name),
      DBI::dbQuoteIdentifier(con, col_nm)
    )
    res <- DBI::dbGetQuery(con, sql)
    res$column <- col_nm
    tibble::as_tibble(res[, c("column", "value", "n")])
  })

  do.call(rbind, results)
}
