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
  cli::cli_warn("Function {.fn il_cleanup} is not yet implemented.")
  invisible(NULL)
}
