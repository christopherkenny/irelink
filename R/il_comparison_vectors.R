#' Comparison Vector Distribution
#'
#' Computes the distribution of gamma patterns (agreement vectors)
#' across record pairs. Each unique combination of gamma values across
#' comparisons is a "comparison vector". This function counts how often
#' each pattern occurs.
#'
#' On DuckDB/PostgreSQL, the computation runs entirely in SQL.
#'
#' @param model A trained `il_model`.
#' @param blocking A blocking rule created by [block_on()]. If `NULL`,
#'   uses all blocking rules from the model spec.
#' @param limit Maximum number of pairs to sample. Defaults to `NULL`
#'   (all pairs).
#'
#' @return A [tibble::tibble()] with one row per unique comparison vector and
#'   columns `gamma_<col>` for each comparison plus `count` (number
#'   of pairs with that pattern) and `proportion`. Class
#'   `il_comparison_vectors`.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_exact()) |>
#'   il_compare(surname, cl_exact())
#' model <- il_model(fake_20, spec = spec, con = con)
#' vectors <- il_comparison_vectors(model)
#' ggplot2::autoplot(vectors)
#' il_cleanup(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_comparison_vectors <- function(model, blocking = NULL, limit = NULL) {
  validate_il_model(model)

  blocking_rules <- model$spec$blocking_rules
  if (!is.null(blocking)) {
    blocking_rules <- list(blocking)
  }

  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  gamma_cols <- paste0('gamma_', comp_names)

  con <- model$con
  dialect <- detect_dialect(con)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL path: GROUP BY + COUNT entirely in-database
    gamma_sql <- build_gamma_query(model, blocking_rules, limit = limit)
    group_cols <- sql_identifier_csv(gamma_cols)
    sql <- glue::glue(
      'SELECT {group_cols}, COUNT(*) AS count ',
      'FROM ({gamma_sql}) __cv ',
      'GROUP BY {group_cols} ',
      'ORDER BY count DESC'
    )
    agg <- DBI::dbGetQuery(con, sql)
  } else {
    # R fallback for SQLite / no connection
    result <- get_pairs_with_gammas(model, blocking_rules, limit = limit)
    gamma_mat <- result$gamma_mat

    if (nrow(gamma_mat) == 0L) {
      cli::cli_abort(
        'No pairs generated. Use a less restrictive blocking rule.'
      )
    }

    gamma_df <- as.data.frame(gamma_mat)
    colnames(gamma_df) <- gamma_cols

    agg <- stats::aggregate(
      rep(1L, nrow(gamma_df)),
      by = as.list(gamma_df),
      FUN = sum
    )
    colnames(agg)[ncol(agg)] <- 'count'
    agg <- agg[order(-agg$count), ]
  }

  if (nrow(agg) == 0L) {
    cli::cli_abort('No pairs generated. Use a less restrictive blocking rule.')
  }

  agg$proportion <- agg$count / sum(agg$count)

  add_class(tibble::as_tibble(agg), 'il_comparison_vectors')
}

