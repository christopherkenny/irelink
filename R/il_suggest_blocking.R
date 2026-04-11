#' Suggest Blocking Rules
#'
#' Enumerates single-column blocking rules and ranks them by a heuristic
#' that balances pair reduction against field coverage. Useful for choosing
#' initial blocking rules before training.
#'
#' @param .data A data frame, dbplyr `tbl_lazy`, or character table name.
#' @param columns Character vector of column names to evaluate. When
#'   `NULL` (the default), all non-ID columns are tried.
#' @param con A DBI connection object. Optional when `.data` is already
#'   registered in the database.
#' @param link_type One of `"dedupe"` (default) or `"link"`.
#' @param max_depth Maximum number of columns to combine in a single
#'   blocking rule. Defaults to `1` (single-column rules only).
#'   Set to `2` to also evaluate two-column combinations.
#'
#' @return A tibble with columns `rule`, `n_distinct`, `coverage`,
#'   `n_pairs`, `pct_of_cartesian`, and `score`, sorted by `score`
#'   descending. Higher scores indicate better blocking rules.
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
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' il_suggest_blocking(df, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_suggest_blocking <- function(.data, columns = NULL, con = NULL,
                                link_type = c('dedupe', 'link'),
                                max_depth = 1L) {
  link_type <- match.arg(link_type)
  max_depth <- as.integer(max_depth)

  tbl_name <- '__il_suggest'
  reg <- register_data(.data,
    con = con, tbl_name = tbl_name,
    add_unique_id = TRUE
  )
  con <- reg$con
  on.exit(drop_registered(con, tbl_name), add = TRUE)
  n <- reg$n_records

  if (is.null(columns)) {
    all_cols <- DBI::dbListFields(con, tbl_name)
    columns <- setdiff(all_cols, c('unique_id', '__source_table'))
  }

  n <- as.numeric(n)
  if (link_type == 'dedupe') {
    cartesian <- n * (n - 1) / 2
  } else {
    cartesian <- n^2
  }

  # Evaluate single-column rules
  candidates <- evaluate_column_combos(
    con, tbl_name, columns, n, cartesian, link_type,
    depth = 1L
  )

  # Optionally evaluate two-column combos
  if (max_depth >= 2L && length(columns) >= 2L) {
    combos_2 <- evaluate_column_combos(
      con, tbl_name, columns, n, cartesian, link_type,
      depth = 2L
    )
    candidates <- rbind(candidates, combos_2)
  }

  candidates <- candidates[order(-candidates$score), ]
  rownames(candidates) <- NULL
  candidates
}

#' Evaluate column combinations for blocking
#' @noRd
evaluate_column_combos <- function(con, tbl_name, columns, n, cartesian,
                                   link_type, depth = 1L) {
  if (depth == 1L) {
    col_sets <- as.list(columns)
  } else {
    col_sets <- utils::combn(columns, depth, simplify = FALSE)
  }

  results <- lapply(col_sets, function(cols) {
    null_filters <- paste(
      vapply(cols, function(c) glue::glue('{c} IS NOT NULL'), character(1)),
      collapse = ' AND '
    )

    # n_distinct
    sql_distinct <- glue::glue(
      'SELECT COUNT(*) AS n FROM (',
      'SELECT DISTINCT {paste(cols, collapse = ", ")} FROM {tbl_name} WHERE {null_filters}',
      ') AS __d'
    )
    n_distinct <- as.integer(DBI::dbGetQuery(con, sql_distinct)$n[1])

    # coverage: % of rows with non-NULL values in all columns
    sql_coverage <- glue::glue(
      'SELECT COUNT(*) AS n FROM {tbl_name} WHERE {null_filters}'
    )
    n_covered <- as.integer(DBI::dbGetQuery(con, sql_coverage)$n[1])
    coverage <- n_covered / n

    # pair count
    where <- build_blocking_condition(cols, where = NULL)
    n_pairs <- count_blocked_pairs(con, tbl_name, tbl_name, where,
      dedupe = (link_type == 'dedupe')
    )
    pct <- if (cartesian > 0) n_pairs / cartesian * 100 else 0

    # Score: high coverage × high reduction (low pct)
    reduction <- 1 - pct / 100
    score <- coverage * reduction

    tibble::tibble(
      rule = paste(cols, collapse = ' & '),
      n_distinct = n_distinct,
      coverage = round(coverage, 4),
      n_pairs = as.integer(n_pairs),
      pct_of_cartesian = round(pct, 4),
      score = round(score, 4)
    )
  })

  do.call(rbind, results)
}

#' Find Blocking Rules Below a Pair-Count Threshold
#'
#' Searches for single-column (and optionally two-column) blocking rules
#' that keep the total number of candidate pairs below a given ceiling.
#'
#' @param .data A data frame, dbplyr `tbl_lazy`, or character table name.
#' @param max_pairs Maximum number of pairs allowed.
#' @param columns Character vector of column names. `NULL` for all.
#' @param con A DBI connection object.
#' @param link_type One of `"dedupe"` (default) or `"link"`.
#' @param max_depth Maximum depth of column combinations (default `2`).
#'
#' @return A tibble of qualifying blocking rules, sorted by `n_pairs`
#'   ascending. Empty tibble if no rules qualify.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' il_find_blocking_below(fake_1000, max_pairs = 100000, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_find_blocking_below <- function(.data, max_pairs, columns = NULL,
                                   con = NULL,
                                   link_type = c('dedupe', 'link'),
                                   max_depth = 2L) {
  candidates <- il_suggest_blocking(
    .data,
    columns = columns, con = con,
    link_type = link_type, max_depth = max_depth
  )
  below <- candidates[candidates$n_pairs <= max_pairs, , drop = FALSE]
  below[order(below$n_pairs), ]
}

#' Derive Blocking Rules from Labelled Pairs
#'
#' For each column, computes the fraction of true-match pairs that share
#' the same value (recall). Helps identify which columns make effective
#' blocking keys.
#'
#' @param .data A data frame or character table name.
#' @param labels A data frame with `unique_id_l`, `unique_id_r`, and
#'   `is_match`.
#' @param columns Character vector of column names to evaluate. `NULL`
#'   for all non-ID columns.
#' @param con A DBI connection.
#'
#' @return A tibble with columns `column`, `recall` (fraction of true
#'   matches caught), and `n_matches_caught`.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' block_from_labels(fake_1000, fake_1000_labels, con = con)
#' DBI::dbDisconnect(con, shutdown = TRUE)
block_from_labels <- function(.data, labels, columns = NULL, con = NULL) {
  tbl_name <- '__il_bfl'
  reg <- register_data(.data,
    con = con, tbl_name = tbl_name,
    add_unique_id = TRUE
  )
  con <- reg$con
  on.exit(drop_registered(con, tbl_name), add = TRUE)

  if (is.null(columns)) {
    all_cols <- DBI::dbListFields(con, tbl_name)
    columns <- setdiff(all_cols, c('unique_id', '__source_table'))
  }

  # Filter to true matches only
  true_matches <- labels[as.logical(labels$is_match), , drop = FALSE]
  if (nrow(true_matches) == 0L) {
    return(tibble::tibble(
      column = character(0),
      recall = numeric(0),
      n_matches_caught = integer(0)
    ))
  }

  n_true <- nrow(true_matches)
  id_l <- as.character(true_matches$unique_id_l)
  id_r <- as.character(true_matches$unique_id_r)
  all_ids <- unique(c(id_l, id_r))
  id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

  col_select <- paste(c('unique_id', columns), collapse = ', ')
  sql_fetch <- glue::glue(
    'SELECT {col_select} FROM {tbl_name} WHERE unique_id IN ({id_list})'
  )
  src <- DBI::dbGetQuery(con, sql_fetch)
  rownames(src) <- as.character(src$unique_id)

  results <- lapply(columns, function(col) {
    val_l <- src[id_l, col]
    val_r <- src[id_r, col]
    caught <- !is.na(val_l) & !is.na(val_r) & val_l == val_r
    tibble::tibble(
      column = col,
      recall = sum(caught) / n_true,
      n_matches_caught = as.integer(sum(caught))
    )
  })

  out <- do.call(rbind, results)
  out[order(-out$recall), ]
}
