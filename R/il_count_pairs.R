#' Count Candidate Pairs Under Blocking Rules
#'
#' Estimates how many record pairs each blocking rule generates without
#' performing full comparisons. Useful for tuning blocking strategies
#' before training. Too many pairs is slow, while too few misses matches.
#'
#' @param .data A data frame, dbplyr `tbl_lazy`, or character table name
#'   (first or only dataset).
#' @param ... Blocking rules created by [block_on()], and optionally
#'   additional datasets for linkage.
#' @param con A DBI connection object. Optional when `.data` is a
#'   `tbl_lazy`.
#' @param link_type One of `"dedupe"` (default) or `"link"`.
#'
#' @return A tibble with columns `rule` and `n_pairs`. When blocking rules
#'   are supplied, it also includes `cumulative_pairs` and
#'   `pct_of_cartesian`.
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
il_count_pairs <- function(
  .data,
  ...,
  con = NULL,
  link_type = c('dedupe', 'link')
) {
  link_type <- match.arg(link_type)
  dots <- list(...)

  # Separate blocking rules from extra datasets
  blocking_rules <- list()
  extra_inputs <- list()
  for (d in dots) {
    if (inherits(d, 'il_blocking_rule')) {
      blocking_rules <- c(blocking_rules, list(d))
    } else {
      extra_inputs <- c(extra_inputs, list(d))
    }
  }

  tbl_l <- il_scratch_table_name('pairs_l')
  reg_l <- register_data(
    .data,
    con = con,
    tbl_name = tbl_l,
    add_unique_id = TRUE
  )
  con <- reg_l$con
  on.exit(drop_registered(con, tbl_l), add = TRUE)

  # Register phonetic SQL macros if needed
  register_phonetic_macros(con)

  if (link_type == 'link' && length(extra_inputs) > 0L) {
    tbl_r <- il_scratch_table_name('pairs_r')
    reg_r <- register_data(
      extra_inputs[[1]],
      con = con,
      tbl_name = tbl_r,
      add_unique_id = TRUE
    )
    on.exit(drop_registered(con, tbl_r), add = TRUE)
  } else {
    tbl_r <- tbl_l
  }

  n_l <- as.numeric(reg_l$n_records)

  if (length(blocking_rules) == 0L) {
    if (link_type == 'dedupe') {
      n_pairs <- n_l * (n_l - 1) / 2
    } else {
      n_r <- n_l
      if (exists('reg_r')) {
        n_r <- as.numeric(reg_r$n_records)
      }
      n_pairs <- n_l * n_r
    }
    return(tibble::tibble(rule = 'cartesian', n_pairs = n_pairs))
  }

  # Compute cartesian for percentage calculation
  if (link_type == 'dedupe') {
    cartesian <- n_l * (n_l - 1) / 2
  } else if (length(extra_inputs) > 0L) {
    n_r <- n_l
    if (exists('reg_r')) {
      n_r <- as.numeric(reg_r$n_records)
    }
    cartesian <- n_l * n_r
  } else {
    cartesian <- n_l^2
  }

  dialect <- detect_dialect(con)

  results <- lapply(blocking_rules, function(rule) {
    where <- build_blocking_condition(
      rule$columns,
      rule$where,
      transform = rule$transform,
      dialect = dialect
    )
    n <- count_blocked_pairs(
      con,
      tbl_l,
      tbl_r,
      where,
      dedupe = (link_type == 'dedupe')
    )
    label <- rule$where
    if (length(rule$columns) > 0L) {
      parts <- paste(rule$columns, collapse = ' & ')
      label <- parts
      if (!is.null(rule$where)) {
        label <- paste0(parts, ' + SQL')
      }
    }
    tibble::tibble(
      rule = label,
      n_pairs = as.numeric(n)
    )
  })

  out <- do.call(rbind, results)

  # Compute cumulative unique pairs via SQL UNION
  cum_parts <- character(0)
  cum_pairs <- numeric(length(blocking_rules))
  for (i in seq_along(blocking_rules)) {
    rule <- blocking_rules[[i]]
    where <- build_blocking_condition(
      rule$columns,
      rule$where,
      transform = rule$transform,
      dialect = dialect
    )
    dedup_cond <- ''
    if (link_type == 'dedupe') {
      dedup_cond <- 'l.unique_id < r.unique_id AND '
    }
    cum_parts <- c(
      cum_parts,
      glue::glue(
        'SELECT l.unique_id AS lid, r.unique_id AS rid ',
        'FROM {tbl_l} l, {tbl_r} r ',
        'WHERE {dedup_cond}{where}'
      )
    )
    union_sql <- paste(cum_parts, collapse = ' UNION ')
    count_sql <- glue::glue('SELECT COUNT(*) AS n FROM ({union_sql}) AS __cum')
    cum_pairs[i] <- as.numeric(DBI::dbGetQuery(con, count_sql)$n[1])
  }

  out$cumulative_pairs <- cum_pairs
  out$pct_of_cartesian <- round(cum_pairs / cartesian * 100, 4)

  add_class(out, 'il_count_pairs')
}
