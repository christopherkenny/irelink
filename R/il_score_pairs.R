#' Score Record Pairs with a Trained Model
#'
#' Scores every pair formed by one record from `records_l` and one record from
#' `records_r`, without blocking. This is useful for scoring a single known
#' pair, checking a handful of candidate matches, or clerical review. For
#' blocked scoring of new records against a model's data, use
#' [il_find_matches()].
#'
#' Term-frequency adjustments use the model's own term-frequency tables, which
#' come from its full data, rather than frequencies within the few records
#' being scored. A model with term-frequency comparisons therefore needs its
#' data attached, via [il_model()] or [il_attach()], or its tables registered
#' with [il_register_tf()].
#'
#' @param model A trained `il_model` object.
#' @param records_l,records_r Data frames of records to compare. Every record
#'   in `records_l` is compared with every record in `records_r`. A
#'   `unique_id` column is added when missing.
#' @param con A DBI connection object from [DBI::dbConnect()]. Defaults to the
#'   model's connection, or a temporary DuckDB connection when the model has
#'   none.
#'
#' @return An `il_compared` tibble with one row per pair, containing
#'   `unique_id_l` and `unique_id_r` (ids within `records_l` and `records_r`),
#'   `match_weight`, `total_match_weight`, `match_probability`, the comparison
#'   levels, and the compared fields.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname)
#' model <- il_model(fake_1000, spec = spec, con = con) |>
#'   il_estimate_u() |>
#'   il_estimate_em(block_on(dob))
#'
#' il_score_pairs(
#'   model,
#'   data.frame(first_name = 'Jon', surname = 'Smith', dob = '1990-01-15'),
#'   data.frame(
#'     first_name = c('John', 'Jane'),
#'     surname = c('Smith', 'Smyth'),
#'     dob = c('1990-01-15', '1985-06-02')
#'   )
#' )
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_score_pairs <- function(model, records_l, records_r, con = NULL) {
  validate_trained_model(model)
  if (!is.data.frame(records_l) || !is.data.frame(records_r)) {
    cli::cli_abort(
      '{.arg records_l} and {.arg records_r} must be data frames.'
    )
  }

  con <- con %||% model$con
  tf_cols <- tf_columns(model$spec$comparisons)
  has_model_tf <- !is.null(model$data$tf_tables) && identical(con, model$con)
  if (length(tf_cols) > 0L && !has_model_tf) {
    cli::cli_abort(c(
      'Term-frequency adjustments for {.field {tf_cols}} need the model\'s term-frequency tables.',
      i = 'Attach the model\'s data with {.fn il_attach} or register tables with {.fn il_register_tf}, then score with the model\'s connection.'
    ))
  }
  if (is.null(con)) {
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  prefix <- il_new_table_prefix()
  reg_l <- register_data(records_l, con = con, tbl_name = paste0(prefix, '_l'))
  on.exit(drop_registered(con, reg_l$tbl_name), add = TRUE)
  reg_r <- register_data(records_r, con = con, tbl_name = paste0(prefix, '_r'))
  on.exit(drop_registered(con, reg_r$tbl_name), add = TRUE)

  spec_cols <- get_spec_columns(model$spec)
  missing <- unique(c(
    setdiff(spec_cols, reg_l$columns),
    setdiff(spec_cols, reg_r$columns)
  ))
  if (length(missing) > 0L) {
    cli::cli_abort(
      'Column{?s} {.field {missing}} required by the model spec {?is/are} missing from the records.'
    )
  }
  register_phonetic_macros(con)

  scoring <- model
  scoring$con <- con
  scoring$link_type <- 'link'
  # An always-true rule gives every pair on both the SQL and R-side paths.
  scoring$spec$blocking_rules <- list(block_on(.where = '1 = 1'))
  scoring$data <- list(
    n_records_l = reg_l$n_records,
    n_records_r = reg_r$n_records,
    tbl_l = reg_l$tbl_name,
    tbl_r = reg_r$tbl_name,
    columns = intersect(reg_l$columns, reg_r$columns),
    table_prefix = prefix
  )
  if (has_model_tf) {
    scoring$data$tf_tables <- model$data$tf_tables
  }

  pairs <- predict(scoring, threshold = 0, include_fields = TRUE)
  attr(pairs, 'sql_profile') <- NULL
  attr(pairs, 'model') <- model
  pairs
}
