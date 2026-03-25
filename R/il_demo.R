#' Load a Demo Dataset
#'
#' Returns a built-in demo dataset for experimenting with irelink. The
#' datasets contain synthetic records with deliberate duplicates and
#' typos, mirroring splink's demo data.
#'
#' @param name A character string identifying the demo dataset (e.g.,
#'   `"fake_1000"`).
#'
#' @return A tibble of demo records.
#' @export
#'
#' @examples
#' \dontrun{
#' df <- il_demo("fake_1000")
#' head(df)
#' }
il_demo <- function(name) {
  cli::cli_warn("Function {.fn il_demo} is not yet implemented.")
  invisible(NULL)
}
