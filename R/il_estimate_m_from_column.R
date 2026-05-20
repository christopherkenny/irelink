#' Estimate Match (m) Parameters from a Label Column
#'
#' Learns the m probabilities from a ground-truth identifier column
#' (e.g., Social Security Number) present in the input data. Records
#' sharing the same label value are treated as true matches. This is an
#' alternative to [il_estimate_m_from_labels()], which requires a
#' separate table of pairwise labels.
#'
#' @param model An `il_model` object (piped in).
#' @param label_col The unquoted name of a column in the input data
#'   containing ground-truth entity identifiers.
#'
#' @return An updated `il_model` with estimated m parameters.
#' @export
#'
#' @examples
#' df <- fake_20
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_exact()) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#'
#' model <- il_estimate_m_from_column(model, city)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_estimate_m_from_column <- function(model, label_col) {
  validate_il_model(model)
  col_name <- rlang::as_name(rlang::enquo(label_col))
  con <- model$con
  dialect <- detect_dialect(con)
  tbl <- model$data$tbl_l
  qtbl <- sql_quote_identifier(tbl)
  qlabel_col <- sql_quote_identifier(col_name)
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)

  # Verify label column exists using DBI-portable approach
  tbl_cols <- DBI::dbListFields(con, tbl)
  if (!col_name %in% tbl_cols) {
    cli::cli_abort('Column {.field {col_name}} not found in the data.')
  }

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: within-cluster self-join + gamma computation + aggregation
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
      'FROM {qtbl} l, {qtbl} r ',
      'WHERE l.{qlabel_col} IS NOT NULL AND l.{qlabel_col} = r.{qlabel_col} ',
      'AND l.unique_id < r.unique_id',
      ') AS match_pairs GROUP BY {group_by_clause}'
    )
    counts <- DBI::dbGetQuery(con, sql)

    if (nrow(counts) == 0L) {
      cli::cli_abort(
        'No within-cluster pairs found for column {.field {col_name}}.'
      )
    }

    n_pairs <- sum(counts$n)
  } else {
    # Fallback: pair generation via SQL self-join (works on all backends)
    cols_needed <- unique(c(
      'unique_id',
      col_name,
      vapply(comparisons, function(c) c$columns, character(1))
    ))
    sel <- build_select_aliases(cols_needed)

    sql <- glue::glue(
      'SELECT {sel$left}, {sel$right} ',
      'FROM {qtbl} l, {qtbl} r ',
      'WHERE l.{qlabel_col} IS NOT NULL AND l.{qlabel_col} = r.{qlabel_col} ',
      'AND l.unique_id < r.unique_id'
    )
    pairs <- DBI::dbGetQuery(con, sql)

    if (nrow(pairs) == 0L) {
      cli::cli_abort(
        'No within-cluster pairs found for column {.field {col_name}}.'
      )
    }

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
  }

  # Compute per-level m frequencies from aggregated pattern counts
  levels_per_comp <- vapply(
    comparisons,
    function(c) n_gamma_levels(c$method),
    integer(1)
  )
  gamma_cols <- paste0('gamma_', comp_names)

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
