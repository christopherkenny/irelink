#' Count Candidate Pairs Under Blocking Rules
#'
#' Estimates how many record pairs each blocking rule generates without
#' performing full comparisons. Useful for tuning blocking strategies
#' before training — too many pairs is slow; too few misses matches.
#'
#' @param .data A data frame or tibble (first or only dataset).
#' @param ... Blocking rules created by [block_on()], and optionally
#'   additional data frames for linkage.
#' @param con A DBI connection object used for computation.
#' @param link_type One of `"dedupe"` (default) or `"link"`.
#'
#' @return A tibble with columns `rule`, `pairs_generated`,
#'   `cumulative_pairs`, and `pct_of_cartesian`.
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
#' il_count_pairs(
#'   df,
#'   block_on(surname),
#'   block_on(first_name),
#'   con = con
#' )
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_count_pairs <- function(.data, ..., con,
                           link_type = c('dedupe', 'link')) {
  link_type <- match.arg(link_type)
  dots <- list(...)

  # Separate blocking rules from extra data frames
  blocking_rules <- list()
  extra_dfs <- list()
  for (d in dots) {
    if (inherits(d, 'il_blocking_rule')) {
      blocking_rules <- c(blocking_rules, list(d))
    } else if (is.data.frame(d)) {
      extra_dfs <- c(extra_dfs, list(d))
    }
  }

  tbl_l <- '__il_pairs_l'
  DBI::dbWriteTable(con, tbl_l, .data, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, tbl_l, fail_if_missing = FALSE), add = TRUE)

  if (link_type == 'link' && length(extra_dfs) > 0L) {
    tbl_r <- '__il_pairs_r'
    DBI::dbWriteTable(con, tbl_r, extra_dfs[[1]], overwrite = TRUE)
    on.exit(DBI::dbRemoveTable(con, tbl_r, fail_if_missing = FALSE), add = TRUE)
  } else {
    tbl_r <- tbl_l
  }

  if (length(blocking_rules) == 0L) {
    # Cartesian count
    if (link_type == 'dedupe') {
      n <- nrow(.data)
      n_pairs <- as.integer(n * (n - 1L) / 2L)
    } else {
      n_pairs <- as.integer(nrow(.data) * nrow(extra_dfs[[1]]))
    }
    return(tibble::tibble(rule = 'cartesian', n_pairs = n_pairs))
  }

  results <- lapply(blocking_rules, function(rule) {
    where <- build_blocking_condition(rule$columns, rule$where)
    n <- count_blocked_pairs(con, tbl_l, tbl_r, where,
      dedupe = (link_type == 'dedupe')
    )
    label <- if (length(rule$columns) > 0L) paste(rule$columns, collapse = ' & ') else rule$where
    tibble::tibble(
      rule = label,
      n_pairs = as.integer(n)
    )
  })

  do.call(rbind, results)
}
