#' Remove Model-Owned Temporary Tables from Database
#'
#' Cleans up the temporary tables owned by a single `il_model`. This is safe
#' to call on a shared DBI connection containing other live `irelink` models.
#' Use [il_cleanup_all()] only when you explicitly want to remove every
#' `irelink` table from the connection.
#'
#' @param model An `il_model` object whose connection and tables should
#'   be cleaned up.
#'
#' @return `model`, invisibly.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c(
#'     'John', 'Jon', 'Jane', 'Jane', 'Bob',
#'     'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
#'     'John', 'Jon', 'Jane', 'Janet', 'Bob',
#'     'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
#'   ),
#'   surname = c(
#'     'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Brown', 'White', 'White',
#'     'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Browne', 'White', 'White'
#'   ),
#'   dob = c(
#'     '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
#'     '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
#'     '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
#'     '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
#'     '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
#'   ),
#'   city = c(
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
#'   ),
#'   email = c(
#'     'john@example.com', 'jon@example.com', 'jane@example.com',
#'     'jane@example.com', 'bob@example.com', 'bobby@example.com',
#'     'alice@example.com', 'alicia@example.com', 'tom@example.com',
#'     'thomas@example.com', 'john@example.com', 'jon@example.com',
#'     'jane@example.com', 'janet@example.com', 'bob@example.com',
#'     'robert@example.com', 'alice@example.com', 'alison@example.com',
#'     'tom@example.com', 'tomas@example.com'
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#'
#' il_cleanup(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_cleanup <- function(model) {
  validate_il_model(model)
  con <- model$con
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(invisible(model))
  }
  tables <- DBI::dbListTables(con)
  tracked <- character(0)
  if (!is.null(model$data$tables) && nrow(model$data$tables) > 0L) {
    tracked <- model$data$tables$table
  }
  known <- c(
    model$data$tbl_l,
    model$data$tbl_r,
    unlist(model$data$tf_tables %||% list(), use.names = FALSE),
    tracked
  )
  prefix <- model$data$table_prefix
  prefixed <- character(0)
  if (!is.null(prefix)) {
    prefixed <- tables[startsWith(tables, paste0(prefix, '_'))]
  }
  il_tables <- unique(c(known[!is.na(known)], prefixed))
  for (tbl in il_tables) {
    drop_registered(con, tbl)
  }
  invisible(model)
}

#' Remove All irelink Temporary Tables from a Database
#'
#' Drops every table or view whose name starts with `__il_` from a DBI
#' connection. This is intended as an explicit interactive escape hatch after
#' failed runs or exploratory sessions. Prefer [il_cleanup()] when cleaning up a
#' specific live model on a shared connection.
#'
#' @param con A DBI connection.
#'
#' @return `con`, invisibly.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' # ... exploratory work that may have created several irelink models ...
#' il_cleanup_all(con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_cleanup_all <- function(con) {
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(invisible(con))
  }
  tables <- DBI::dbListTables(con)
  il_tables <- tables[grepl('^__il_', tables)]
  for (tbl in il_tables) {
    drop_registered(con, tbl)
  }
  invisible(con)
}
