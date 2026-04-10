#' Save a Model to Disk
#'
#' Serialises a trained `il_model` object to an RDS file so that it can be
#' loaded later without re-training. The database connection and any
#' in-database tables are not stored; supply a fresh connection with
#' [il_attach()] after loading.
#'
#' @param model A trained `il_model` object.
#' @param path A file path (character string) where the model will be
#'   saved.
#' @param overwrite If `TRUE`, overwrite an existing file at `path`.
#'   Defaults to `FALSE`.
#'
#' @return `model`, invisibly.
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
#' tmp <- tempfile(fileext = '.rds')
#'
#' il_save(model, tmp)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_save <- function(model, path, overwrite = FALSE) {
  validate_il_model(model)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(
      'File {.file {path}} already exists. Use {.code overwrite = TRUE} to overwrite.'
    )
  }

  saveable <- list(
    spec = model$spec,
    params = model$params,
    trained = model$trained,
    link_type = model$link_type,
    data_info = list(
      n_records_l = model$data$n_records_l,
      n_records_r = model$data$n_records_r,
      columns = model$data$columns
    )
  )

  saveRDS(saveable, path)
  invisible(model)
}

#' Load a Saved Model
#'
#' Reads a previously saved `il_model` object from disk. The loaded model
#' is ready for prediction without re-training, though a fresh database
#' connection may need to be supplied via [il_attach()].
#'
#' @param path A file path (character string) to a saved model.
#'
#' @return An `il_model` object.
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
#' tmp <- tempfile(fileext = '.rds')
#' il_save(model, tmp)
#'
#' loaded <- il_load(tmp)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_load <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort('File {.file {path}} does not exist.')
  }

  raw <- readRDS(path)

  new_il_model(
    spec = raw$spec,
    data = list(
      n_records_l = raw$data_info$n_records_l,
      n_records_r = raw$data_info$n_records_r,
      columns = raw$data_info$columns
    ),
    con = NULL,
    link_type = raw$link_type %||% 'dedupe',
    params = raw$params,
    trained = isTRUE(raw$trained)
  )
}
