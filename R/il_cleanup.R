#' Remove Temporary Tables from Database
#'
#' Cleans up all temporary tables created by irelink in the database
#' backend. Call this when you are finished with a linkage session to
#' free database resources.
#'
#' @param model An `il_model` object whose connection and tables should
#'   be cleaned up.
#'
#' @return `model`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' il_cleanup(model)
#' }
il_cleanup <- function(model) {
  validate_il_model(model)
  con <- model$con
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(invisible(model))
  }
  tables <- DBI::dbListTables(con)
  il_tables <- tables[grepl("^__il_", tables)]
  for (tbl in il_tables) {
    DBI::dbRemoveTable(con, tbl, fail_if_missing = FALSE)
  }
  invisible(model)
}
