#' Column Completeness Across Datasets
#'
#' Computes the percentage of non-null values for each column across one
#' or more datasets.
#'
#' @param ... One or more data frames, dbplyr `tbl_lazy` references, or
#'   character table names to profile.
#' @param con A DBI connection object. Optional when all inputs are
#'   `tbl_lazy` references.
#'
#' @return A tibble with columns `table`, `column`, `n_total`,
#'   `n_non_null`, and `pct_non_null`.
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
#' il_completeness(df, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_completeness <- function(..., con = NULL) {
  inputs <- list(...)
  results <- list()

  for (i in seq_along(inputs)) {
    tbl_name <- il_scratch_table_name(paste0('completeness_', i))
    reg <- register_data(inputs[[i]],
      con = con, tbl_name = tbl_name,
      add_unique_id = FALSE
    )
    con <- reg$con
    on.exit(drop_registered(con, tbl_name), add = TRUE)

    n_total <- reg$n_records
    col_names <- reg$columns

    rows <- lapply(col_names, function(col_nm) {
      quoted_col <- DBI::dbQuoteIdentifier(con, col_nm)
      quoted_tbl <- DBI::dbQuoteIdentifier(con, tbl_name)
      sql <- glue::glue('SELECT COUNT({quoted_col}) AS n_non_null FROM {quoted_tbl}')
      res <- DBI::dbGetQuery(con, sql)
      tibble::tibble(
        table = paste0('table_', i),
        column = col_nm,
        n_total = n_total,
        n_non_null = as.integer(res$n_non_null),
        pct_non_null = as.numeric(res$n_non_null) / n_total * 100
      )
    })

    results <- c(results, rows)
  }

  do.call(rbind, results) |>
    add_class('il_completeness')
}
