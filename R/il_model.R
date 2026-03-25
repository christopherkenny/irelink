#' Create a Linkage Model
#'
#' Binds one or more data frames to a specification and a database
#' connection, producing an untrained model. This is analogous to how
#' [dplyr::tbl()] binds a connection to a table name and returns a lazy
#' reference.
#'
#' @param .data A data frame or tibble. The first (or only) input dataset.
#' @param ... Additional data frames for multi-table linkage.
#' @param spec An `il_spec` object built with [il_spec()], [il_compare()],
#'   and [il_block_on()].
#' @param con A DBI connection object (e.g., from
#'   `DBI::dbConnect(duckdb::duckdb())`).
#' @param link_type One of `"dedupe"` (default), `"link"`, or
#'   `"link_and_dedupe"`.
#'
#' @return An untrained `il_model` object, ready for training verbs.
#' @export
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
#'
#' # Deduplication (one dataset)
#' model <- il_model(voters, spec = spec, con = con)
#'
#' # Linkage (two datasets)
#' model <- il_model(
#'   voters_2020, voters_2024,
#'   spec = spec, con = con, link_type = "link"
#' )
#' }
il_model <- function(.data, ..., spec, con,
                     link_type = c("dedupe", "link", "link_and_dedupe")) {
  cli::cli_warn("Function {.fn il_model} is not yet implemented.")
  invisible(NULL)
}

#' Print an irelink Model
#'
#' Displays a human-readable summary of the model's type, data, training
#' status, comparisons, and blocking rules.
#'
#' @param x An `il_model` object.
#' @param ... Additional arguments passed to [print()].
#'
#' @return `x`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' print(model)
#' }
print.il_model <- function(x, ...) {
  cli::cli_warn("Function {.fn print.il_model} is not yet implemented.")
  invisible(x)
}

#' Summarise an irelink Model
#'
#' Prints a detailed table of trained parameters including m and u
#' probabilities, match weights, and the prior match probability for
#' each comparison level.
#'
#' @param object An `il_model` object.
#' @param ... Additional arguments passed to [summary()].
#'
#' @return A summary object, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' summary(model)
#' }
summary.il_model <- function(object, ...) {
  cli::cli_warn("Function {.fn summary.il_model} is not yet implemented.")
  invisible(NULL)
}

#' Test if an Object is an irelink Model
#'
#' Returns `TRUE` if `x` inherits from class `il_model`.
#'
#' @param x An object to test.
#'
#' @return A single logical value.
#' @export
#'
#' @examples
#' \dontrun{
#' is_il_model(model)
#' }
is_il_model <- function(x) {
  inherits(x, "il_model")
}
