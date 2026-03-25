#' Save a Model to Disk
#'
#' Serialises a trained `il_model` object to a file so that it can be
#' loaded later without re-training.
#'
#' @param model A trained `il_model` object.
#' @param path A file path (character string) where the model will be
#'   saved.
#'
#' @return `model`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' il_save(model, "my_model.rds")
#' }
il_save <- function(model, path) {
  cli::cli_warn("Function {.fn il_save} is not yet implemented.")
  invisible(NULL)
}

#' Load a Saved Model
#'
#' Reads a previously saved `il_model` object from disk. The loaded model
#' is ready for prediction without re-training, though a fresh database
#' connection may need to be supplied.
#'
#' @param path A file path (character string) to a saved model.
#'
#' @return An `il_model` object.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_load("my_model.rds")
#' }
il_load <- function(path) {
  cli::cli_warn("Function {.fn il_load} is not yet implemented.")
  invisible(NULL)
}
