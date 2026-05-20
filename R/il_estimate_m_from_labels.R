#' Estimate Match (m) Parameters from Labeled Data
#'
#' Learns the m probabilities (the probability of observing each
#' comparison level given that the records **do** match) from a set of
#' pre-labeled record pairs. Use this instead of [il_estimate_em()] when
#' ground-truth labels are available.
#'
#' @param model An `il_model` object (piped in).
#' @param labels A data frame of labeled pairs with columns identifying
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
  if (!is.data.frame(labels)) {
    cli::cli_abort('{.arg labels} must be a data frame.')
  }
  required <- c('unique_id_l', 'unique_id_r', 'is_match')
  missing <- setdiff(required, names(labels))
  if (length(missing) > 0L) {
    cli::cli_abort(
      '{.arg labels} must contain column{?s} {.field {missing}}.'
    )
  }
  if (anyNA(labels$is_match)) {
    cli::cli_abort('{.field is_match} must not contain missing values.')
  }
  if (is.logical(labels$is_match)) {
    labels$is_match <- as.logical(labels$is_match)
  } else if (
    is.numeric(labels$is_match) &&
      all(labels$is_match %in% c(0, 1))
  ) {
    labels$is_match <- labels$is_match == 1
  } else {
    cli::cli_abort('{.field is_match} must be logical or numeric 0/1.')
  }
  if (anyNA(labels$unique_id_l) || anyNA(labels$unique_id_r)) {
    cli::cli_abort('Label unique ID columns must not contain missing values.')
  }
  con <- model$con
  dialect <- detect_dialect(con)
  tbl <- model$data$tbl_l
  qtbl <- sql_quote_identifier(tbl)
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)

  match_pairs <- labels[labels$is_match, ]
  if (nrow(match_pairs) == 0L) {
    cli::cli_abort('No matching pairs found in labels.')
  }

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: upload match labels, JOIN to data, compute gammas, aggregate
    lbl_tbl <- il_table_name(model, 'm_labels', il_table_suffix())
    lbl_df <- data.frame(
      uid_l = as.character(match_pairs$unique_id_l),
      uid_r = as.character(match_pairs$unique_id_r),
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(con, lbl_tbl, as.data.frame(lbl_df), overwrite = TRUE)
    on.exit(drop_registered(con, lbl_tbl), add = TRUE)

    gamma_exprs <- vapply(
      comparisons,
      function(comp) {
        expr <- sql_gamma_case(comp, dialect)
        glue::glue(
          '{expr} AS {sql_quote_identifier(paste0("gamma_", comparison_name(comp)))}'
        )
      },
      character(1)
    )
    gamma_select <- paste(gamma_exprs, collapse = ', ')
    gamma_cols <- paste0('gamma_', comp_names)
    group_by_clause <- sql_identifier_csv(gamma_cols)

    sql <- glue::glue(
      'SELECT {group_by_clause}, COUNT(*) AS n FROM (',
      'SELECT {gamma_select} ',
      'FROM {sql_quote_identifier(lbl_tbl)} lbl ',
      'JOIN {qtbl} l ON l.unique_id = lbl.uid_l ',
      'JOIN {qtbl} r ON r.unique_id = lbl.uid_r',
      ') AS match_pairs GROUP BY {group_by_clause}'
    )
    counts <- DBI::dbGetQuery(con, sql)

    if (nrow(counts) == 0L) {
      cli::cli_abort('No matching pairs found in labels.')
    }

    n_pairs <- sum(counts$n)
  } else {
    # Fallback: fetch only the needed rows via SQL WHERE clause
    all_ids <- unique(c(
      as.character(match_pairs$unique_id_l),
      as.character(match_pairs$unique_id_r)
    ))
    id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')
    sql <- glue::glue(
      'SELECT * FROM {qtbl} WHERE unique_id IN ({id_list})'
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
    gamma_cols <- paste0('gamma_', comp_names)
    counts_df <- as.data.frame(gamma_mat)
    names(counts_df) <- gamma_cols
    counts <- stats::aggregate(
      list(n = rep(1L, nrow(gamma_mat))),
      by = counts_df,
      FUN = sum
    )
    n_pairs <- nrow(gamma_mat)
    comp_names <- colnames(gamma_mat)
  }

  # Compute per-level m frequencies from aggregated pattern counts
  levels_per_comp <- vapply(
    comparisons,
    function(c) n_gamma_levels(c$method),
    integer(1)
  )
  gamma_cols <- paste0('gamma_', comp_names)

  # Merge with existing parameters
  if (!is.null(model$params$comparisons)) {
    params <- model$params$comparisons
    if ('level' %in% names(params) && !'gamma_level' %in% names(params)) {
      params <- migrate_params_to_gamma_level(params)
    }
    for (j in seq_along(comp_names)) {
      cn <- comp_names[j]
      gcol <- gamma_cols[j]
      nl <- levels_per_comp[j]
      for (k in seq(0L, nl - 1L)) {
        count_k <- sum(counts$n[counts[[gcol]] == k], na.rm = TRUE)
        m_k <- max(count_k / n_pairs, 0.001)
        row_idx <- params$comparison == cn & params$gamma_level == k
        if (any(row_idx)) {
          params$m[row_idx] <- m_k
        }
      }
    }
    # Normalize m within each comparison
    for (cn in comp_names) {
      idx <- params$comparison == cn
      m_vals <- params$m[idx]
      params$m[idx] <- m_vals / sum(m_vals)
    }
    model$params$comparisons <- params
  } else {
    rows <- list()
    for (j in seq_along(comp_names)) {
      cn <- comp_names[j]
      gcol <- gamma_cols[j]
      nl <- levels_per_comp[j]
      for (k in seq(0L, nl - 1L)) {
        count_k <- sum(counts$n[counts[[gcol]] == k], na.rm = TRUE)
        m_k <- max(count_k / n_pairs, 0.001)
        rows <- c(
          rows,
          list(data.frame(
            comparison = cn,
            gamma_level = k,
            m = m_k,
            u = NA_real_,
            stringsAsFactors = FALSE
          ))
        )
      }
    }
    params_tbl <- tibble::as_tibble(do.call(rbind, rows))
    # Normalize m within each comparison
    for (cn in comp_names) {
      idx <- params_tbl$comparison == cn
      m_vals <- params_tbl$m[idx]
      params_tbl$m[idx] <- m_vals / sum(m_vals)
    }
    model$params$comparisons <- params_tbl
  }

  model$trained <- TRUE
  model
}
