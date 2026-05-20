#' Profile Column Value Distributions
#'
#' Computes summary statistics and value-frequency distributions for
#' selected columns of a dataset. Useful for understanding data quality
#' before defining comparison rules. Accepts data frames,
#' [dbplyr::tbl_lazy] table references, or character table names.
#'
#' @param .data A data frame, [dbplyr::tbl_lazy], or character table name.
#' @param ... Columns to profile, specified as unquoted names or as
#'   character strings containing raw SQL expressions (e.g.,
#'   `"city || ' ' || first_name"`). If empty, all columns are profiled.
#' @param con A DBI connection object from [DBI::dbConnect()]. Optional when `.data` is a
#'   [dbplyr::tbl_lazy].
#' @param top_n Integer. Number of most-frequent values to return per
#'   column. Defaults to `NULL` (return all values).
#' @param bottom_n Integer. Number of least-frequent values to return per
#'   column. Defaults to `NULL` (return all values).
#'
#' @return A [tibble::tibble()] of per-column summary statistics.
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
#' il_profile(df, first_name, surname, con = con, top_n = 5)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_profile <- function(.data, ..., con = NULL, top_n = NULL, bottom_n = NULL) {
  col_exprs <- rlang::enquos(...)

  tbl_name <- il_scratch_table_name('profile')
  reg <- register_data(
    .data,
    con = con,
    tbl_name = tbl_name,
    add_unique_id = FALSE
  )
  con <- reg$con
  on.exit(drop_registered(con, tbl_name), add = TRUE)

  # Build a list of (label, sql_expr) pairs.
  # A character literal like "city || left(name,1)" is used as raw SQL;
  # a bare name like `first_name` is quoted as an identifier.
  if (length(col_exprs) == 0L) {
    col_specs <- lapply(reg$columns, function(nm) {
      list(label = nm, sql_expr = as.character(DBI::dbQuoteIdentifier(con, nm)))
    })
  } else {
    col_specs <- lapply(col_exprs, function(q) {
      expr <- rlang::quo_get_expr(q)
      if (is.character(expr)) {
        list(label = expr, sql_expr = expr)
      } else {
        nm <- as.character(expr)
        list(
          label = nm,
          sql_expr = as.character(DBI::dbQuoteIdentifier(con, nm))
        )
      }
    })
  }

  quoted_tbl <- DBI::dbQuoteIdentifier(con, tbl_name)

  results <- lapply(col_specs, function(spec) {
    sql <- glue::glue(
      'SELECT {spec$sql_expr} AS value, COUNT(*) AS n FROM {quoted_tbl} ',
      'GROUP BY {spec$sql_expr} ORDER BY n DESC'
    )
    res <- DBI::dbGetQuery(con, sql)
    res$column <- spec$label
    out <- tibble::as_tibble(res[, c('column', 'value', 'n')])

    if (!is.null(top_n) || !is.null(bottom_n)) {
      top <- NULL
      if (!is.null(top_n)) {
        top <- utils::head(out, top_n)
      }
      bot <- NULL
      if (!is.null(bottom_n)) {
        bot <- utils::tail(out, bottom_n)
      }
      out <- unique(rbind(top, bot))
    }

    out
  })

  add_class(do.call(rbind, results), 'il_profile')
}
