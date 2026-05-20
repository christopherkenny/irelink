#' Construct an il_model Object
#'
#' Low-level constructor for the `il_model` S3 class. Users should call
#' [il_model()] instead.
#'
#' @param spec An `il_spec` object.
#' @param data A list of data frames.
#' @param con A DBI connection from [DBI::dbConnect()] or `NULL`.
#' @param link_type A character string.
#' @param params A list of trained parameters.
#' @param trained Logical indicating whether the model has been trained.
#'
#' @return An `il_model` object.
#' @noRd
new_il_model <- function(
  spec = new_il_spec(),
  data = list(),
  con = NULL,
  link_type = 'dedupe',
  params = list(),
  trained = FALSE
) {
  structure(
    list(
      spec = spec,
      data = data,
      con = con,
      link_type = link_type,
      params = params,
      trained = trained
    ),
    class = 'il_model'
  )
}

#' Validate an il_model Object
#'
#' Checks that `x` inherits from `il_model` and aborts with an
#' informative error if not.
#'
#' @param x An object to validate.
#'
#' @return `x`, invisibly.
#' @noRd
validate_il_model <- function(x) {
  if (!inherits(x, 'il_model')) {
    cli::cli_abort('{.arg model} must be an {.cls il_model} object.')
  }
  invisible(x)
}

#' Create a Linkage Model
#'
#' Binds one or more datasets to a specification and a database
#' connection, producing an untrained model. Accepts in-memory data
#' frames, [dbplyr::tbl_lazy] table references, or character table names for
#' data that already lives in a database.
#'
#' When `.data` is a [dbplyr::tbl_lazy] (from [dplyr::tbl()]), the connection
#' is extracted automatically and data stays in-database with zero
#' copying. A `unique_id` column is injected automatically if not
#' already present.
#'
#' @param .data A data frame, [tibble::tibble()], [dbplyr::tbl_lazy], or character
#'   table name. The first (or only) input dataset. If no `unique_id`
#'   column is present, one is generated automatically.
#' @param ... Additional datasets for multi-table linkage (same types
#'   as `.data`).
#' @param spec An `il_spec` object built with [il_spec()], [il_compare()],
#'   and [il_block_on()].
#' @param con A DBI connection object from [DBI::dbConnect()] (e.g., from
#'   `DBI::dbConnect(duckdb::duckdb())`). Optional when `.data` is a
#'   [dbplyr::tbl_lazy], the connection is extracted from the table reference.
#' @param link_type One of `"dedupe"` (default), `"link"`, or
#'   `"link_and_dedupe"`.
#'
#' @return An untrained `il_model` object, ready for training verbs.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
#'
#' model <- il_model(fake_20, spec = spec, con = con)
#'
#' # Database-backed: pass a dbplyr reference directly
#' DBI::dbWriteTable(con, 'my_data', fake_20, overwrite = TRUE)
#' tbl_ref <- dplyr::tbl(con, 'my_data')
#' model2 <- il_model(tbl_ref, spec = spec)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_model <- function(
  .data,
  ...,
  spec,
  con = NULL,
  link_type = c('dedupe', 'link', 'link_and_dedupe')
) {
  link_type <- match.arg(link_type)
  extra_inputs <- list(...)
  if (length(extra_inputs) > 1L) {
    cli::cli_abort(
      '{.fn il_model} accepts at most two datasets: {.arg .data} and one additional dataset.'
    )
  }

  validate_il_spec(spec)

  table_prefix <- il_new_table_prefix()

  # Register primary data (normalizes all input types)
  reg_l <- register_data(
    .data,
    con = con,
    tbl_name = paste0(table_prefix, '_data_l')
  )
  con <- reg_l$con
  spec <- resolve_spec_selectors(spec, reg_l$columns, reg_l$column_classes)

  # Register phonetic SQL macros if any transforms require them
  register_phonetic_macros(con)

  # Validate columns referenced in spec exist in data
  spec_cols <- get_spec_columns(spec)
  missing_cols <- setdiff(spec_cols, reg_l$columns)
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      'Column{?s} {.field {missing_cols}} referenced in the spec but not found in the data.'
    )
  }

  if (
    link_type %in% c('link', 'link_and_dedupe') && length(extra_inputs) == 0L
  ) {
    cli::cli_abort(
      '{.arg link_type} is {.val {link_type}} but only one dataset was provided. Supply a second data frame.'
    )
  }

  # Register right-side data if present
  tbl_name_r <- NULL
  n_records_r <- NULL
  if (length(extra_inputs) > 0L) {
    reg_r <- register_data(
      extra_inputs[[1]],
      con = con,
      tbl_name = paste0(table_prefix, '_data_r')
    )
    missing_cols_r <- setdiff(spec_cols, reg_r$columns)
    if (length(missing_cols_r) > 0L) {
      cli::cli_abort(
        'Column{?s} {.field {missing_cols_r}} referenced in the spec but not found in the right data.'
      )
    }
    tbl_name_r <- reg_r$tbl_name
    n_records_r <- reg_r$n_records
  }

  data_info <- list(
    n_records_l = reg_l$n_records,
    n_records_r = n_records_r,
    tbl_l = reg_l$tbl_name,
    tbl_r = tbl_name_r,
    columns = reg_l$columns,
    table_prefix = table_prefix,
    tables = data.frame(
      table = c(reg_l$tbl_name, tbl_name_r)[
        !is.na(c(reg_l$tbl_name, tbl_name_r))
      ],
      owner = 'model',
      stringsAsFactors = FALSE
    )
  )

  new_il_model(
    spec = spec,
    data = data_info,
    con = con,
    link_type = link_type,
    params = list(),
    trained = FALSE
  ) |>
    compute_tf_tables()
}

#' Attach a Saved Model to Fresh Data
#'
#' Takes a loaded (or existing) `il_model` and binds it to new data and a
#' fresh database connection, producing a model ready for [predict()] or
#' further training. Accepts in-memory data frames, [dbplyr::tbl_lazy] table
#' references, or character table names.
#'
#' This is the key function for the production workflow:
#' train once with [il_model()] -> save with [il_save()] -> later, load
#' with [il_load()] and attach to new data with `il_attach()`.
#'
#' The loaded model's trained parameters (m, u, prior) are preserved.
#' You can immediately call [predict()] on the attached model, or
#' continue training with [il_estimate_em()] using the existing
#' parameters as a warm start.
#'
#' @param model An `il_model` object, typically from [il_load()].
#' @param .data A data frame, [tibble::tibble()], [dbplyr::tbl_lazy], or character
#'   table name. The first (or only) input dataset.
#' @param ... Additional datasets for multi-table linkage.
#' @param con A DBI connection object from [DBI::dbConnect()]. Optional when `.data` is a
#'   [dbplyr::tbl_lazy], the connection is extracted from the table reference.
#' @param link_type Optionally override the model's link type. If `NULL`
#'   (default), uses the link type stored in the model.
#'
#' @return The model, now connected to `con` with data uploaded, ready
#'   for [predict()], [il_find_matches()], or further training.
#' @export
#'
#' @examples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
#' model <- il_model(fake_1000, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' path <- tempfile(fileext = '.rds')
#' il_save(model, path)
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' con2 <- DBI::dbConnect(duckdb::duckdb())
#' loaded <- il_load(path)
#' model2 <- il_attach(loaded, fake_1000, con = con2)
#' DBI::dbDisconnect(con2, shutdown = TRUE)
il_attach <- function(model, .data, ..., con = NULL, link_type = NULL) {
  validate_il_model(model)

  link_type <- link_type %||% model$link_type %||% 'dedupe'
  link_type <- match.arg(link_type, c('dedupe', 'link', 'link_and_dedupe'))
  extra_inputs <- list(...)
  if (length(extra_inputs) > 1L) {
    cli::cli_abort(
      '{.fn il_attach} accepts at most two datasets: {.arg .data} and one additional dataset.'
    )
  }

  table_prefix <- il_new_table_prefix()

  # Register primary data
  reg_l <- register_data(
    .data,
    con = con,
    tbl_name = paste0(table_prefix, '_data_l')
  )
  con <- reg_l$con
  model$spec <- resolve_spec_selectors(
    model$spec,
    reg_l$columns,
    reg_l$column_classes
  )

  # Register phonetic SQL macros if needed
  register_phonetic_macros(con)

  # Validate columns
  spec_cols <- get_spec_columns(model$spec)
  missing_cols <- setdiff(spec_cols, reg_l$columns)
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      'Column{?s} {.field {missing_cols}} referenced in the model spec but not found in the data.'
    )
  }

  if (
    link_type %in% c('link', 'link_and_dedupe') && length(extra_inputs) == 0L
  ) {
    cli::cli_abort(
      '{.arg link_type} is {.val {link_type}} but only one dataset was provided. Supply a second data frame.'
    )
  }

  # Register right-side data if present
  tbl_name_r <- NULL
  n_records_r <- NULL
  if (length(extra_inputs) > 0L) {
    reg_r <- register_data(
      extra_inputs[[1]],
      con = con,
      tbl_name = paste0(table_prefix, '_data_r')
    )
    missing_cols_r <- setdiff(spec_cols, reg_r$columns)
    if (length(missing_cols_r) > 0L) {
      cli::cli_abort(
        'Column{?s} {.field {missing_cols_r}} referenced in the model spec but not found in the right data.'
      )
    }
    tbl_name_r <- reg_r$tbl_name
    n_records_r <- reg_r$n_records
  }

  data_info <- list(
    n_records_l = reg_l$n_records,
    n_records_r = n_records_r,
    tbl_l = reg_l$tbl_name,
    tbl_r = tbl_name_r,
    columns = reg_l$columns,
    table_prefix = table_prefix,
    tables = data.frame(
      table = c(reg_l$tbl_name, tbl_name_r)[
        !is.na(c(reg_l$tbl_name, tbl_name_r))
      ],
      owner = 'model',
      stringsAsFactors = FALSE
    )
  )

  model$data <- data_info
  model$con <- con
  model$link_type <- link_type

  compute_tf_tables(model)
}

#' Print an irelink Model
#'
#' Displays a human-readable summary of the model's type, data, training
#' status, comparisons, and blocking rules.
#'
#' @param x An `il_model` object.
#' @param ... Additional arguments passed to [print()].
#'
#' @return `x`, invisibly.
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
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' print(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
print.il_model <- function(x, ...) {
  status <- 'Untrained'
  if (x$trained) {
    status <- 'Trained'
  }
  n_records <- x$data$n_records_l
  n_comparisons <- length(x$spec$comparisons)
  n_blocking <- length(x$spec$blocking_rules)

  cat('irelink Model\n')
  cat(sprintf('  Status: %s\n', status))
  cat(sprintf('  Link type: %s\n', x$link_type))
  cat(sprintf('  Records: %d\n', n_records))
  if (!is.null(x$data$n_records_r)) {
    cat(sprintf('  Records (right): %d\n', x$data$n_records_r))
  }
  cat(sprintf('  Comparisons: %d\n', n_comparisons))
  cat(sprintf('  Blocking rules: %d\n', n_blocking))
  invisible(x)
}

#' Summarize an irelink Model
#'
#' Prints a detailed table of trained parameters including m and u
#' probabilities, match weights, and the prior match probability for
#' each comparison level.
#'
#' @param object An `il_model` object.
#' @param ... Additional arguments passed to [summary()].
#'
#' @return A summary object, invisibly.
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
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' summary(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
summary.il_model <- function(object, ...) {
  print.il_model(object, ...)
  if (object$trained) {
    cat('\n  Parameters:\n')
    params <- object$params
    if (length(params) > 0L) {
      for (nm in setdiff(names(params), 'history')) {
        cat(sprintf('    %s: %s\n', nm, format(params[[nm]])))
      }
    }
  }
  invisible(object)
}

#' Test if an Object is an irelink Model
#'
#' Returns `TRUE` if `x` inherits from class `il_model`.
#'
#' @param x An object to test.
#'
#' @return A single logical value.
#' @export
#'
#' @examples
#' is_il_model(il_spec())
is_il_model <- function(x) {
  inherits(x, 'il_model')
}
