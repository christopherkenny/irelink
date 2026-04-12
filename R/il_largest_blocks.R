#' Identify the Largest Blocking Bins
#'
#' For a given blocking rule, returns the `n` blocking-key combinations
#' that produce the most record pairs. Useful for diagnosing skew — a
#' single dominant key can create a quadratic explosion of pairs.
#'
#' @param .data A data frame, dbplyr `tbl_lazy`, or character table name
#'   (first or only dataset).
#' @param rule A blocking rule created by [block_on()].
#' @param n Integer. Number of largest bins to return. Defaults to `5`.
#' @param con A DBI connection object. Optional when `.data` is a
#'   `tbl_lazy`.
#' @param link_type One of `"dedupe"` (default) or `"link"`.
#'
#' @return A tibble with one row per blocking-key combination, sorted by
#'   descending pair count. Columns are the blocking-key values plus
#'   `n_records` and `n_pairs`.
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
#'   city = c(
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' il_largest_blocks(df, block_on(city), n = 3, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_largest_blocks <- function(.data, rule, n = 5L, con = NULL,
                              link_type = c('dedupe', 'link')) {
  link_type <- match.arg(link_type)
  n <- as.integer(n)

  if (!inherits(rule, 'il_blocking_rule')) {
    cli::cli_abort('{.arg rule} must be a blocking rule from {.fn block_on}.')
  }
  if (length(rule$columns) == 0L) {
    cli::cli_abort(
      '{.fn il_largest_blocks} requires column-based blocking (not SQL-only {.arg .where}).'
    )
  }

  tbl_name <- '__il_largest_tmp'
  reg <- register_data(.data,
    con = con, tbl_name = tbl_name,
    add_unique_id = FALSE
  )
  con <- reg$con
  on.exit(drop_registered(con, tbl_name), add = TRUE)

  cols <- rule$columns
  group_cols <- paste(cols, collapse = ', ')

  sql <- glue::glue(
    'SELECT {group_cols}, COUNT(*) AS n_records ',
    'FROM {tbl_name} ',
    'WHERE {paste(glue::glue("{cols} IS NOT NULL"), collapse = " AND ")} ',
    'GROUP BY {group_cols} ',
    'ORDER BY n_records DESC ',
    'LIMIT {n}'
  )

  res <- DBI::dbGetQuery(con, sql)

  if (link_type == 'dedupe') {
    res$n_pairs <- as.numeric(res$n_records) * (as.numeric(res$n_records) - 1) / 2
  } else {
    res$n_pairs <- as.numeric(res$n_records)^2
  }

  tibble::as_tibble(res)
}
