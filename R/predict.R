#' Score Record Pairs from a Trained Model
#'
#' Generates and scores all candidate record pairs that pass the blocking
#' rules, returning those above the match-probability threshold. This is
#' an S3 method for [stats::predict()] — the same generic used for `lm`,
#' `glm`, and tidymodels objects.
#'
#' @param object A trained `il_model` object.
#' @param threshold A numeric value between 0 and 1. Only pairs with a
#'   match probability at or above this threshold are returned. Defaults
#'   to `0.85`. Ignored when `threshold_match_weight` is set.
#' @param threshold_match_weight Optional numeric value. When set, pairs
#'   are filtered on match weight (log₂ Bayes factor) instead of
#'   probability. Typical values range from about −5 to +30. Overrides
#'   `threshold`.
#' @param type One of `"pairs"` (default) to return scored pairs, or
#'   `"weights"` to return match weights on a log-2 Bayes-factor scale.
#' @param collect If `TRUE` (the default), scored pairs are collected
#'   into an in-memory tibble.
#'   If `FALSE`, scoring is performed entirely in-database and the
#'   result is a lightweight `il_compared_lazy` reference that
#'   [il_cluster()] can consume directly — avoiding the round-trip of
#'   collecting millions of rows into R and re-uploading them.
#'   Requires a DuckDB or PostgreSQL backend.
#' @param include_fields If `TRUE`, the original column values from both
#'   records in each pair are included in the output (suffixed `_l` and
#'   `_r`). Defaults to `FALSE` for performance. When `collect = FALSE`
#'   the join is performed in-database before the table is created.
#' @param greedy If `TRUE`, keep a deterministic one-to-one greedy matching
#'   for link models. Defaults to `FALSE`, returning all above-threshold
#'   candidate pairs. Greedy matching sorts pairs by descending posterior
#'   match probability, then by left and right row order.
#' @param ... Additional arguments passed to the generic.
#'
#' @return When `collect = TRUE`: an `il_compared` tibble with one row
#'   per candidate pair, including columns for record IDs, match weight,
#'   match probability, and per-comparison gamma values.
#'   When `collect = FALSE`: an `il_compared_lazy` object referencing the
#'   scored pairs table in the database.
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
#' model <- il_estimate_em(model, block_on(surname))
#'
#' pairs <- predict(model, threshold = 0.5)
#' DBI::dbDisconnect(con, shutdown = TRUE)
predict.il_model <- function(object, threshold = 0.85,
                             threshold_match_weight = NULL,
                             type = c('pairs', 'weights'),
                             collect = TRUE,
                             include_fields = FALSE,
                             greedy = FALSE,
                             ...) {
  type <- match.arg(type)
  validate_il_model(object)

  if (!object$trained) {
    cli::cli_abort('Model must be trained before prediction. Use {.fn il_estimate_em} first.')
  }

  if (!is.logical(greedy) || length(greedy) != 1L || is.na(greedy)) {
    cli::cli_abort('{.arg greedy} must be `TRUE` or `FALSE`.')
  }

  if (greedy && !identical(object$link_type, 'link')) {
    cli::cli_abort(
      '{.arg greedy = TRUE} is only supported when {.code link_type = "link"}.'
    )
  }

  # Lazy path: push scoring entirely into SQL
  if (!collect) {
    dialect <- detect_dialect(object$con)
    if (!dialect_has_fuzzy_sql(dialect)) {
      cli::cli_abort(
        '{.arg collect = FALSE} requires a DuckDB or PostgreSQL backend.'
      )
    }
    return(predict_lazy(object, threshold,
      threshold_match_weight = threshold_match_weight,
      include_fields = include_fields,
      greedy = greedy
    ))
  }

  # SQL-first collect path for DuckDB/PostgreSQL:
  # Score, filter, and deduplicate in SQL; only collect the final result.
  dialect <- detect_dialect(object$con)
  if (dialect_has_fuzzy_sql(dialect)) {
    scored_sql <- build_scored_query(object, threshold,
      threshold_match_weight = threshold_match_weight
    )
    if (greedy) {
      result <- tibble::as_tibble(DBI::dbGetQuery(object$con, scored_sql))
      result <- greedy_match_pairs(result, model = object)
      if (include_fields) {
        result <- join_original_fields(result, object)
      }
    } else if (include_fields) {
      scored_sql <- build_fields_join_query(object, scored_sql)
      result <- tibble::as_tibble(DBI::dbGetQuery(object$con, scored_sql))
    } else {
      result <- tibble::as_tibble(DBI::dbGetQuery(object$con, scored_sql))
    }
    if (nrow(result) == 0L) {
      empty <- tibble::tibble(
        unique_id_l = integer(0), unique_id_r = integer(0),
        match_weight = numeric(0), match_probability = numeric(0)
      )
      return(new_il_compared(empty, model = object))
    }
    return(new_il_compared(result, model = object))
  }

  # R-side fallback for SQLite and other backends
  comparisons <- object$spec$comparisons
  params <- object$params$comparisons
  prior <- safe_prior(object)
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  blocking_rules <- object$spec$blocking_rules

  result_data <- get_pairs_with_gammas(object, blocking_rules)
  gamma_mat <- result_data$gamma_mat
  ids <- result_data$ids

  if (nrow(gamma_mat) == 0L) {
    empty <- tibble::tibble(
      unique_id_l = integer(0), unique_id_r = integer(0),
      match_weight = numeric(0), match_probability = numeric(0)
    )
    return(new_il_compared(empty, model = object))
  }

  n_comp <- length(comparisons)
  mu <- extract_mu_vectors(params, comp_names)
  match_weight <- score_gamma_matrix(gamma_mat, mu)

  # Apply term-frequency adjustments
  tf_cols <- tf_columns(comparisons)
  tf_adj_list <- NULL
  if (length(tf_cols) > 0L && !is.null(result_data$tf_data)) {
    tf_adj <- compute_tf_adjustment(
      gamma_mat, result_data$tf_data, comparisons, mu
    )
    match_weight <- match_weight + tf_adj
    tf_adj_list <- compute_tf_adjustment_matrix(
      gamma_mat, result_data$tf_data, comparisons, mu
    )
  }

  match_probability <- weight_to_probability(match_weight, prior)

  result <- tibble::tibble(
    unique_id_l = ids$l_unique_id,
    unique_id_r = ids$r_unique_id,
    match_weight = match_weight,
    match_probability = match_probability
  )
  for (j in seq_len(n_comp)) {
    result[[paste0('gamma_', comp_names[j])]] <- gamma_mat[, j]
  }

  # Store per-comparison TF adjustments for waterfall
  if (!is.null(tf_adj_list)) {
    for (col in names(tf_adj_list)) {
      result[[paste0('tf_adj_', col)]] <- tf_adj_list[[col]]
    }
  }

  if (!is.null(threshold_match_weight)) {
    result <- result[result$match_weight >= threshold_match_weight, , drop = FALSE]
  } else {
    result <- result[result$match_probability >= threshold, , drop = FALSE]
  }
  result <- tibble::as_tibble(result)

  if (greedy) {
    result <- greedy_match_pairs(result, model = object)
  }

  if (include_fields) {
    result <- join_original_fields(result, object)
  }

  new_il_compared(result, model = object)
}

#' SQL-side prediction (lazy path)
#'
#' Pushes gamma computation, scoring, TF adjustment, and threshold
#' filtering entirely into SQL.  Returns an `il_compared_lazy` reference.
#'
#' @param model A trained il_model.
#' @param threshold Numeric match-probability threshold.
#' @param threshold_match_weight Optional numeric match-weight threshold.
#' @return An `il_compared_lazy` object.
#' @noRd
predict_lazy <- function(model, threshold, threshold_match_weight = NULL,
                         include_fields = FALSE,
                         greedy = FALSE) {
  con <- model$con
  predicted_tbl <- '__il_predicted'
  scored_sql <- build_scored_query(model, threshold,
    threshold_match_weight = threshold_match_weight
  )
  if (greedy) {
    scored_sql <- build_greedy_query(model, scored_sql)
  }
  if (include_fields) {
    scored_sql <- build_fields_join_query(model, scored_sql)
  }

  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {predicted_tbl}'))
  DBI::dbExecute(con, glue::glue(
    'CREATE TABLE {predicted_tbl} AS {scored_sql}'
  ))
  new_il_compared_lazy(
    con = con,
    predicted_tbl = predicted_tbl,
    model = model,
    threshold = threshold
  )
}

#' Apply deterministic greedy one-to-one matching to scored pairs
#'
#' Sorts scored pairs by descending posterior match probability, then by
#' left and right source row order, and keeps the first pair whose left
#' and right records have not already been used.
#'
#' @param pairs A scored-pairs tibble.
#' @param model The `il_model` that produced the pairs.
#' @param row_index_l Optional integer vector of left row indices.
#' @param row_index_r Optional integer vector of right row indices.
#' @return A tibble of one-to-one greedy matches.
#' @noRd
greedy_match_pairs <- function(pairs, model = NULL,
                               row_index_l = NULL,
                               row_index_r = NULL) {
  if (nrow(pairs) == 0L) {
    return(pairs)
  }

  if (is.null(row_index_l) || is.null(row_index_r)) {
    row_index <- pair_row_indices(pairs, model %||% attr(pairs, 'model'))
    row_index_l <- row_index$row_index_l
    row_index_r <- row_index$row_index_r
  }

  if (length(row_index_l) != nrow(pairs) || length(row_index_r) != nrow(pairs)) {
    cli::cli_abort('Greedy matching row indices must have one entry per pair.')
  }

  if (anyNA(row_index_l) || anyNA(row_index_r)) {
    cli::cli_abort(
      'Greedy matching could not map all predicted pairs back to source row indices.'
    )
  }

  order_idx <- order(-pairs$match_probability, row_index_l, row_index_r)
  ordered_pairs <- tibble::as_tibble(pairs[order_idx, , drop = FALSE])

  used_l <- new.env(parent = emptyenv())
  used_r <- new.env(parent = emptyenv())
  keep <- logical(nrow(ordered_pairs))

  for (i in seq_len(nrow(ordered_pairs))) {
    key_l <- as.character(ordered_pairs$unique_id_l[i])
    key_r <- as.character(ordered_pairs$unique_id_r[i])

    if (!exists(key_l, envir = used_l, inherits = FALSE) &&
      !exists(key_r, envir = used_r, inherits = FALSE)) {
      keep[i] <- TRUE
      assign(key_l, TRUE, envir = used_l)
      assign(key_r, TRUE, envir = used_r)
    }
  }

  result <- tibble::as_tibble(ordered_pairs[keep, , drop = FALSE])
  if (inherits(pairs, 'il_compared')) {
    return(new_il_compared(result, model = model %||% attr(pairs, 'model')))
  }

  result
}

#' Resolve source row indices for scored pairs
#' @param pairs A scored-pairs tibble.
#' @param model The `il_model` that produced the pairs.
#' @return A list with `row_index_l` and `row_index_r`.
#' @noRd
pair_row_indices <- function(pairs, model) {
  if (is.null(model)) {
    cli::cli_abort(
      'Greedy matching needs the originating model to resolve source row indices.'
    )
  }

  lookup_l <- row_index_lookup(model$con, model$data$tbl_l)
  tbl_r <- model$data$tbl_r %||% model$data$tbl_l
  lookup_r <- if (identical(tbl_r, model$data$tbl_l)) {
    lookup_l
  } else {
    row_index_lookup(model$con, tbl_r)
  }

  list(
    row_index_l = unname(lookup_l[as.character(pairs$unique_id_l)]),
    row_index_r = unname(lookup_r[as.character(pairs$unique_id_r)])
  )
}

#' Build a unique_id -> row-index lookup for a registered source table
#' @param con A DBI connection.
#' @param tbl Table name.
#' @return A named integer vector.
#' @noRd
row_index_lookup <- function(con, tbl) {
  ids <- DBI::dbGetQuery(
    con,
    glue::glue('SELECT unique_id FROM {tbl}')
  )$unique_id
  lookup <- seq_along(ids)
  names(lookup) <- as.character(ids)
  lookup
}

#' Join original field values into predicted pairs
#'
#' Fetches column values from the source tables for all IDs appearing
#' in the result and merges them with `_l` / `_r` suffixes.
#'
#' @param result A tibble of predicted pairs (must have unique_id_l/r).
#' @param model The il_model.
#' @return The result tibble with additional field columns.
#' @noRd
join_original_fields <- function(result, model) {
  if (nrow(result) == 0L) {
    return(result)
  }

  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL JOIN path: upload result IDs to temp table, JOIN to source data
    tmp_tbl <- '__il_field_join'
    id_df <- data.frame(
      row_idx = seq_len(nrow(result)),
      uid_l = as.character(result$unique_id_l),
      uid_r = as.character(result$unique_id_r),
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(con, tmp_tbl, id_df, overwrite = TRUE)
    on.exit(drop_registered(con, tmp_tbl), add = TRUE)

    all_cols <- DBI::dbListFields(con, tbl_l)
    field_cols <- setdiff(all_cols, 'unique_id')
    if (length(field_cols) == 0L) {
      return(result)
    }

    l_select <- paste0('sl.', field_cols, ' AS ', field_cols, '_l', collapse = ', ')
    if (tbl_r == tbl_l) {
      r_field_cols <- field_cols
    } else {
      r_field_cols <- setdiff(DBI::dbListFields(con, tbl_r), 'unique_id')
    }
    r_select <- paste0('sr.', r_field_cols, ' AS ', r_field_cols, '_r', collapse = ', ')

    sql <- glue::glue(
      'SELECT t.row_idx, {l_select}, {r_select} ',
      'FROM {tmp_tbl} t ',
      'JOIN {tbl_l} sl ON sl.unique_id = t.uid_l ',
      'JOIN {tbl_r} sr ON sr.unique_id = t.uid_r ',
      'ORDER BY t.row_idx'
    )
    fields <- DBI::dbGetQuery(con, sql)
    fields$row_idx <- NULL

    return(tibble::as_tibble(cbind(result, fields)))
  }

  # R-side fallback for non-fuzzy-SQL dialects
  all_ids <- unique(c(
    as.character(result$unique_id_l),
    as.character(result$unique_id_r)
  ))
  id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

  all_cols <- DBI::dbListFields(con, tbl_l)
  field_cols <- setdiff(all_cols, 'unique_id')
  if (length(field_cols) == 0L) {
    return(result)
  }

  col_select <- paste(c('unique_id', field_cols), collapse = ', ')
  sql_l <- glue::glue('SELECT {col_select} FROM {tbl_l} WHERE unique_id IN ({id_list})')
  src_l <- DBI::dbGetQuery(con, sql_l)
  rownames(src_l) <- as.character(src_l$unique_id)

  if (tbl_r == tbl_l) {
    src_r <- src_l
  } else {
    all_cols_r <- DBI::dbListFields(con, tbl_r)
    field_cols_r <- setdiff(all_cols_r, 'unique_id')
    col_select_r <- paste(c('unique_id', field_cols_r), collapse = ', ')
    sql_r <- glue::glue('SELECT {col_select_r} FROM {tbl_r} WHERE unique_id IN ({id_list})')
    src_r <- DBI::dbGetQuery(con, sql_r)
    rownames(src_r) <- as.character(src_r$unique_id)
  }

  id_l <- as.character(result$unique_id_l)
  id_r <- as.character(result$unique_id_r)
  for (col in field_cols) {
    result[[paste0(col, '_l')]] <- src_l[id_l, col]
  }
  r_cols <- if (tbl_r == tbl_l) field_cols else setdiff(DBI::dbListFields(con, tbl_r), 'unique_id')
  for (col in r_cols) {
    result[[paste0(col, '_r')]] <- src_r[id_r, col]
  }

  result
}
