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
#'   to `0.85`.
#' @param type One of `"pairs"` (default) to return scored pairs, or
#'   `"weights"` to return match weights on a log-2 Bayes-factor scale.
#' @param collect If `TRUE` (the default), scored pairs are collected
#'   into an in-memory tibble.
#'   If `FALSE`, scoring is performed entirely in-database and the
#'   result is a lightweight `il_compared_lazy` reference that
#'   [il_cluster()] can consume directly — avoiding the round-trip of
#'   collecting millions of rows into R and re-uploading them.
#'   Requires a DuckDB or PostgreSQL backend.
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
                             type = c('pairs', 'weights'),
                             collect = TRUE, ...) {
  type <- match.arg(type)
  validate_il_model(object)

  if (!object$trained) {
    cli::cli_abort('Model must be trained before prediction. Use {.fn il_estimate_em} first.')
  }

  # Lazy path: push scoring entirely into SQL
  if (!collect) {
    dialect <- detect_dialect(object$con)
    if (!dialect_has_fuzzy_sql(dialect)) {
      cli::cli_abort(
        '{.arg collect = FALSE} requires a DuckDB or PostgreSQL backend.'
      )
    }
    return(predict_lazy(object, threshold))
  }

  comparisons <- object$spec$comparisons
  params <- object$params$comparisons
  prior <- object$params$prior %||% 0.05
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

  result <- result[result$match_probability >= threshold, , drop = FALSE]
  result <- tibble::as_tibble(result)
  new_il_compared(result, model = object)
}

#' SQL-side prediction (lazy path)
#'
#' Pushes gamma computation, scoring, TF adjustment, and threshold
#' filtering entirely into SQL.  Returns an [il_compared_lazy] reference.
#'
#' @param model A trained il_model.
#' @param threshold Numeric match-probability threshold.
#' @return An `il_compared_lazy` object.
#' @noRd
predict_lazy <- function(model, threshold) {
  con <- model$con
  predicted_tbl <- '__il_predicted'
  scored_sql <- build_scored_query(model, threshold)
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
