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
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))

  # Verify label column exists using DBI-portable approach
  tbl_cols <- DBI::dbListFields(con, tbl)
  if (!col_name %in% tbl_cols) {
    cli::cli_abort('Column {.field {col_name}} not found in the data.')
  }

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: within-cluster self-join + gamma computation in SQL
    gamma_exprs <- vapply(comparisons, function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue('{expr} AS gamma_{comp$columns}')
    }, character(1))
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    sql <- glue::glue(
      'SELECT {gamma_select} ',
      'FROM {tbl} l, {tbl} r ',
      'WHERE l.{col_name} IS NOT NULL AND l.{col_name} = r.{col_name} ',
      'AND l.unique_id < r.unique_id'
    )
    result <- DBI::dbGetQuery(con, sql)

    if (nrow(result) == 0L) {
      cli::cli_abort('No within-cluster pairs found for column {.field {col_name}}.')
    }

    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names
  } else {
    # Fallback: pair generation via SQL self-join (works on all backends)
    cols_needed <- unique(c(
      'unique_id', col_name,
      vapply(comparisons, function(c) c$columns, character(1))
    ))
    sel <- build_select_aliases(cols_needed)

    sql <- glue::glue(
      'SELECT {sel$left}, {sel$right} ',
      'FROM {tbl} l, {tbl} r ',
      'WHERE l.{col_name} IS NOT NULL AND l.{col_name} = r.{col_name} ',
      'AND l.unique_id < r.unique_id'
    )
    pairs <- DBI::dbGetQuery(con, sql)

    if (nrow(pairs) == 0L) {
      cli::cli_abort('No within-cluster pairs found for column {.field {col_name}}.')
    }

    gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  }

  m_match <- colMeans(gamma_mat)
  m_nonmatch <- 1 - m_match

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
