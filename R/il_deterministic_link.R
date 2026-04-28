#' Deterministic Record Linkage
#'
#' Finds exact-match record pairs using the blocking rules in the
#' specification, without requiring probabilistic training. This is a
#' common first step before probabilistic linkage — pairs that match on
#' all blocking columns are returned directly.
#'
#' @param .data A data frame, dbplyr `tbl_lazy`, or character table name
#'   (first or only dataset).
#' @param ... Additional datasets for multi-table linkage.
#' @param spec An `il_spec` object with blocking rules defined via
#'   [il_block_on()].
#' @param con A DBI connection object. Optional when `.data` is a
#'   `tbl_lazy`.
#' @param link_type One of `"dedupe"` (default), `"link"`, or
#'   `"link_and_dedupe"`.
#'
#' @return A tibble of exact-match record pairs.
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
#'   il_block_on(first_name, surname, dob)
#'
#' exact_matches <- il_deterministic_link(df, spec = spec, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_deterministic_link <- function(.data, ..., spec, con = NULL,
                                  link_type = c(
                                    'dedupe', 'link',
                                    'link_and_dedupe'
                                  )) {
  link_type <- match.arg(link_type)
  validate_il_spec(spec)

  comparisons <- spec$comparisons
  blocking_rules <- spec$blocking_rules

  tbl_name <- il_scratch_table_name('det_data')
  reg <- register_data(.data, con = con, tbl_name = tbl_name)
  con <- reg$con
  on.exit(drop_registered(con, tbl_name), add = TRUE)

  if (length(blocking_rules) > 0L) {
    dialect <- detect_dialect(con)
    block_sqls <- vapply(blocking_rules, function(br) {
      paste0('(', build_blocking_condition(br$columns,
        transform = br$transform,
        dialect = dialect
      ), ')')
    }, character(1))
    block_where <- paste(block_sqls, collapse = ' OR ')
  } else {
    block_where <- '1 = 1'
  }

  # Push exact-match filter for all comparison columns into SQL
  exact_conds <- vapply(comparisons, function(comp) {
    col <- comp$columns
    glue::glue('l.{col} IS NOT NULL AND r.{col} IS NOT NULL AND l.{col} = r.{col}')
  }, character(1))
  exact_where <- paste(exact_conds, collapse = ' AND ')

  sql <- glue::glue(
    'SELECT l.unique_id AS l_unique_id, r.unique_id AS r_unique_id ',
    'FROM {tbl_name} l, {tbl_name} r ',
    'WHERE l.unique_id < r.unique_id AND ({block_where}) AND {exact_where}'
  )
  pairs <- DBI::dbGetQuery(con, sql)

  if (nrow(pairs) == 0L) {
    return(tibble::tibble(unique_id_l = integer(0), unique_id_r = integer(0)))
  }

  tibble::tibble(
    unique_id_l = pairs$l_unique_id,
    unique_id_r = pairs$r_unique_id
  )
}
