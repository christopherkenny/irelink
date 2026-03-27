#' Save a Model to Disk
#'
#' Serialises a trained `il_model` object to a file so that it can be
#' loaded later without re-training.
#'
#' @param model A trained `il_model` object.
#' @param path A file path (character string) where the model will be
#'   saved.
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
#' tmp <- tempfile(fileext = '.json')
#'
#' il_save(model, tmp)
#' DBI::dbDisconnect(con, shutdown = TRUE)
unclass_comparison_level <- function(x) {
  x <- unclass(x)
  if (!is.null(x$levels)) {
    x$levels <- lapply(x$levels, unclass_comparison_level)
  }
  if (!is.null(x$children)) {
    x$children <- lapply(x$children, unclass_comparison_level)
  }
  if (!is.null(x$child)) {
    x$child <- unclass_comparison_level(x$child)
  }
  x
}

il_save <- function(model, path, overwrite = FALSE) {
  validate_il_model(model)
  if (file.exists(path) && !overwrite) {
    cli::cli_abort(
      'File {.file {path}} already exists. Use {.code overwrite = TRUE} to overwrite.'
    )
  }

  # Serialize spec into plain lists (strip S3 classes for JSON)
  spec_data <- list(
    comparisons = lapply(model$spec$comparisons, function(cmp) {
      list(
        columns = cmp$columns,
        method = unclass_comparison_level(cmp$method)
      )
    }),
    blocking_rules = lapply(model$spec$blocking_rules, function(br) {
      unclass(br)
    })
  )

  # Serialize params (tibbles become data frames, which jsonlite handles)
  params_data <- model$params
  if (inherits(params_data$comparisons, 'tbl_df')) {
    params_data$comparisons <- as.data.frame(params_data$comparisons)
  }
  # Strip any tibbles from history entries
  if (!is.null(params_data$history) && is.list(params_data$history)) {
    params_data$history <- lapply(params_data$history, function(h) {
      if (inherits(h, 'tbl_df')) as.data.frame(h) else h
    })
  }

  data_out <- list(
    spec = spec_data,
    params = params_data,
    trained = model$trained,
    link_type = model$link_type,
    data_info = list(
      n_records_l = model$data$n_records_l,
      n_records_r = model$data$n_records_r,
      columns = model$data$columns
    )
  )

  jsonlite::write_json(data_out, path,
    auto_unbox = TRUE, pretty = TRUE,
    null = 'null', digits = NA
  )
  invisible(model)
}

#' Load a Saved Model
#'
#' Reads a previously saved `il_model` object from disk. The loaded model
#' is ready for prediction without re-training, though a fresh database
#' connection may need to be supplied.
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
#' tmp <- tempfile(fileext = '.json')
#' il_save(model, tmp)
#'
#' loaded <- il_load(tmp)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_load <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort('File {.file {path}} does not exist.')
  }

  raw <- jsonlite::read_json(path, simplifyVector = TRUE)

  # Reconstruct spec
  comparisons <- lapply(seq_len(NROW(raw$spec$comparisons)), function(i) {
    cmp_data <- if (is.data.frame(raw$spec$comparisons)) {
      as.list(raw$spec$comparisons[i, ])
    } else {
      raw$spec$comparisons[[i]]
    }
    method_data <- cmp_data$method
    if (is.character(method_data) || is.list(method_data)) {
      method_data <- as.list(method_data)
    }
    method <- structure(method_data, class = 'il_comparison_level')
    list(columns = cmp_data$columns, method = method)
  })

  blocking_rules <- lapply(seq_len(NROW(raw$spec$blocking_rules)), function(i) {
    br_data <- if (is.data.frame(raw$spec$blocking_rules)) {
      as.list(raw$spec$blocking_rules[i, ])
    } else {
      raw$spec$blocking_rules[[i]]
    }
    structure(br_data, class = 'il_blocking_rule')
  })

  spec <- new_il_spec(comparisons = comparisons, blocking_rules = blocking_rules)

  # Reconstruct params
  params <- raw$params
  if (!is.null(params$comparisons)) {
    params$comparisons <- tibble::as_tibble(as.data.frame(params$comparisons))
  }
  if (!is.null(params$prior) && length(params$prior) == 1L) {
    params$prior <- as.numeric(params$prior)
  }

  data_info <- raw$data_info
  if (!is.null(data_info)) {
    data_info <- as.list(data_info)
  } else {
    data_info <- list()
  }

  new_il_model(
    spec = spec,
    data = data_info,
    con = NULL,
    link_type = raw$link_type %||% 'dedupe',
    params = params,
    trained = isTRUE(raw$trained)
  )
}
