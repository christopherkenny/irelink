#' Estimate Match (m) Parameters from Labelled Data
#'
#' Learns the m probabilities (the probability of observing each
#' comparison level given that the records **do** match) from a set of
#' pre-labelled record pairs. Use this instead of [il_estimate_em()] when
#' ground-truth labels are available.
#'
#' @param model An `il_model` object (piped in).
#' @param labels A data frame of labelled pairs with columns identifying
#'   the left record, right record, and a logical or integer match
#'   indicator.
#'
#' @return An updated `il_model` with estimated m parameters.
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
#' labels <- data.frame(
#'   unique_id_l = c(1L, 1L),
#'   unique_id_r = c(11L, 2L),
#'   is_match = c(1L, 0L)
#' )
#'
#' model <- il_estimate_m_from_labels(model, labels)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_estimate_m_from_labels <- function(model, labels) {
  validate_il_model(model)
  con <- model$con
  dialect <- detect_dialect(con)
  tbl <- model$data$tbl_l
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))

  match_pairs <- labels[labels$is_match == TRUE, ]
  if (nrow(match_pairs) == 0L) {
    cli::cli_abort('No matching pairs found in labels.')
  }

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: upload match labels, JOIN to data, compute gammas in-database
    lbl_tbl <- '__il_m_labels'
    lbl_df <- data.frame(
      uid_l = as.character(match_pairs$unique_id_l),
      uid_r = as.character(match_pairs$unique_id_r),
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(con, lbl_tbl, as.data.frame(lbl_df), overwrite = TRUE)
    on.exit(drop_registered(con, lbl_tbl), add = TRUE)

    gamma_exprs <- vapply(comparisons, function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue('{expr} AS gamma_{comp$columns}')
    }, character(1))
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    sql <- glue::glue(
      'SELECT {gamma_select} ',
      'FROM {lbl_tbl} lbl ',
      'JOIN {tbl} l ON l.unique_id = lbl.uid_l ',
      'JOIN {tbl} r ON r.unique_id = lbl.uid_r'
    )
    result <- DBI::dbGetQuery(con, sql)

    if (nrow(result) == 0L) {
      cli::cli_abort('No matching pairs found in labels.')
    }

    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names
  } else {
    # Fallback: fetch only the needed rows via SQL WHERE clause
    all_ids <- unique(c(
      as.character(match_pairs$unique_id_l),
      as.character(match_pairs$unique_id_r)
    ))
    id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')
    sql <- glue::glue(
      'SELECT * FROM {tbl} WHERE unique_id IN ({id_list})'
    )
    data <- DBI::dbGetQuery(con, sql)
    id_col <- 'unique_id'

    pair_rows <- list()
    cols <- model$data$columns
    for (i in seq_len(nrow(match_pairs))) {
      id_l <- match_pairs$unique_id_l[i]
      id_r <- match_pairs$unique_id_r[i]
      row_l <- data[data[[id_col]] == id_l, , drop = FALSE]
      row_r <- data[data[[id_col]] == id_r, , drop = FALSE]
      if (nrow(row_l) > 0L && nrow(row_r) > 0L) {
        pair <- as.data.frame(c(
          stats::setNames(as.list(row_l[1, ]), paste0('l_', names(row_l))),
          stats::setNames(as.list(row_r[1, ]), paste0('r_', names(row_r)))
        ))
        pair_rows <- c(pair_rows, list(pair))
      }
    }

    if (length(pair_rows) == 0L) {
      cli::cli_abort('No matching pairs found in labels.')
    }

    pairs <- do.call(rbind, pair_rows)
    gamma_mat <- compute_gamma_matrix(pairs, comparisons)
    comp_names <- colnames(gamma_mat)
  }

  m_match <- colMeans(gamma_mat)
  m_nonmatch <- 1 - m_match

  # Merge with existing parameters
  if (!is.null(model$params$comparisons)) {
    params <- model$params$comparisons
    for (j in seq_along(comp_names)) {
      cn <- comp_names[j]
      params$m[params$comparison == cn & params$level == 'match'] <- m_match[j]
      params$m[params$comparison == cn & params$level == 'non_match'] <- m_nonmatch[j]
    }
    model$params$comparisons <- params
  } else {
    model$params$comparisons <- tibble::tibble(
      comparison = rep(comp_names, each = 2L),
      level = rep(c('match', 'non_match'), times = length(comp_names)),
      m = as.numeric(rbind(m_match, m_nonmatch)),
      u = NA_real_
    )
  }

  model$trained <- TRUE
  model
}
