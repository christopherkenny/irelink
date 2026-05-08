#' Compare Two Individual Records
#'
#' Scores a single pair of records against a specification without
#' requiring a full training pipeline. Useful for quick one-off
#' comparisons or debugging.
#'
#' @param record_a A named list or single-row data frame representing the
#'   first record.
#' @param record_b A named list or single-row data frame representing the
#'   second record.
#' @param spec An `il_spec` object describing the comparisons to perform.
#' @param con A DBI connection object. If `NULL` (default), a temporary
#'   DuckDB connection is created and closed on exit.
#'
#' @return A single-row tibble of per-comparison gamma values.
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
#' record_a <- df[1, ]
#' record_b <- df[2, ]
#'
#' il_compare_records(record_a, record_b, spec = spec, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_compare_records <- function(record_a, record_b, spec, con = NULL) {
  validate_il_spec(spec)
  comparisons <- spec$comparisons
  comp_names <- comparison_names(comparisons)

  a <- as.data.frame(record_a, stringsAsFactors = FALSE)
  b <- as.data.frame(record_b, stringsAsFactors = FALSE)
  if (nrow(a) != 1L || nrow(b) != 1L) {
    cli::cli_abort(
      '{.fn il_compare_records} requires each record input to contain exactly one row.'
    )
  }
  needed_cols <- unique(unlist(lapply(comparisons, function(comp) comp$columns)))
  missing_a <- setdiff(needed_cols, names(a))
  missing_b <- setdiff(needed_cols, names(b))
  if (length(missing_a) > 0L || length(missing_b) > 0L) {
    missing <- unique(c(missing_a, missing_b))
    cli::cli_abort(
      'Column{?s} {.field {missing}} required by the spec {?is/are} missing from the record inputs.'
    )
  }

  own_con <- is.null(con)
  if (own_con) {
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  dialect <- detect_dialect(con)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: upload the two records and compute gammas in-database
    tbl_tmp <- il_scratch_table_name('compare_records')
    a_clean <- a[1, setdiff(names(a), 'unique_id'), drop = FALSE]
    b_clean <- b[1, setdiff(names(b), 'unique_id'), drop = FALSE]
    tmp_df <- rbind(
      cbind(a_clean, data.frame(unique_id = 1L)),
      cbind(b_clean, data.frame(unique_id = 2L))
    )
    DBI::dbWriteTable(con, tbl_tmp, as.data.frame(tmp_df), overwrite = TRUE)
    on.exit(drop_registered(con, tbl_tmp), add = TRUE)

    gamma_exprs <- vapply(comparisons, function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue('{expr} AS gamma_{comparison_name(comp)}')
    }, character(1))
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    sql <- glue::glue(
      'SELECT {gamma_select} ',
      'FROM {tbl_tmp} l, {tbl_tmp} r ',
      'WHERE l.unique_id = 1 AND r.unique_id = 2'
    )
    row <- DBI::dbGetQuery(con, sql)

    result <- tibble::tibble(.rows = 1L)
    for (j in seq_along(comp_names)) {
      result[[paste0('gamma_', comp_names[j])]] <- as.integer(row[[paste0('gamma_', comp_names[j])]])
    }
    return(result)
  }

  # Fallback: R-side computation for backends without fuzzy SQL
  pair <- as.data.frame(c(
    stats::setNames(as.list(a[1, , drop = FALSE]), paste0('l_', names(a))),
    stats::setNames(as.list(b[1, , drop = FALSE]), paste0('r_', names(b)))
  ))

  gamma_mat <- compute_gamma_matrix(pair, comparisons)

  result <- tibble::tibble(.rows = 1L)
  for (j in seq_along(comp_names)) {
    result[[paste0('gamma_', comp_names[j])]] <- gamma_mat[1, j]
  }
  result
}
