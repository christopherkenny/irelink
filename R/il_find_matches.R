#' Find Matches for New Records
#'
#' Scores new records against the data already loaded into a trained
#' model. Useful for real-time or incremental matching where new records
#' arrive after the model has been trained.
#'
#' @param model A trained `il_model` object.
#' @param new_records A data frame of new records to match against the
#'   model's existing data.
#' @param threshold A numeric value between 0 and 1. Only matches at or
#'   above this probability are returned. Defaults to `0.85`.
#'
#' @return An `il_compared` tibble of scored pairs between new records
#'   and existing data.
#' @export
#'
#' @examples
#' \dontrun{
#' new_arrivals <- data.frame(
#'   first_name = "Jane", surname = "Doe", dob = "1992-05-10"
#' )
#' il_find_matches(model, new_arrivals, threshold = 0.85)
#' }
il_find_matches <- function(model, new_records, threshold = 0.85) {
  cli::cli_warn("Function {.fn il_find_matches} is not yet implemented.")
  invisible(NULL)
}
