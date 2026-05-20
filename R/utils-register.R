# Internal helper for normalizing data input to a database table reference.
# Supports data.frames, tbl_lazy (dbplyr), and character table name strings.

.il_table_counter <- new.env(parent = emptyenv())
.il_table_counter$n <- 0L

#' Generate a model table prefix
#' @return Character prefix beginning with "__il_".
#' @noRd
il_new_table_prefix <- function() {
  .il_table_counter$n <- .il_table_counter$n + 1L
  paste0('__il_', Sys.getpid(), '_', .il_table_counter$n)
}

#' Generate a short unique table suffix
#' @return Character suffix.
#' @noRd
il_table_suffix <- function() {
  .il_table_counter$n <- .il_table_counter$n + 1L
  as.character(.il_table_counter$n)
}

#' Build a table name scoped to an il_model
#' @param model An il_model object.
#' @param purpose Short table purpose.
#' @param suffix Optional suffix.
#' @return Character table name.
#' @noRd
il_table_name <- function(model, purpose, suffix = NULL) {
  prefix <- model$data$table_prefix %||% il_new_table_prefix()
  parts <- c(prefix, purpose, suffix)
  paste(parts[!is.na(parts) & nzchar(parts)], collapse = '_')
}

#' Build a unique package scratch table name
#' @param purpose Short table purpose.
#' @param suffix Optional suffix.
#' @return Character table name beginning with "__il_".
#' @noRd
il_scratch_table_name <- function(purpose, suffix = NULL) {
  suffix <- suffix %||% il_table_suffix()
  paste(c('__il', purpose, Sys.getpid(), suffix), collapse = '_')
}

#' Track a table in model metadata
#' @param model An il_model object.
#' @param tbl_name Character table name.
#' @param owner One of "model", "call", or "lazy".
#' @return Updated model.
#' @noRd
il_track_table <- function(
  model,
  tbl_name,
  owner = c('model', 'call', 'lazy')
) {
  owner <- match.arg(owner)
  if (is.null(model$data$tables)) {
    model$data$tables <- data.frame(
      table = character(),
      owner = character(),
      stringsAsFactors = FALSE
    )
  }
  existing <- model$data$tables$table == tbl_name
  if (any(existing)) {
    model$data$tables$owner[existing] <- owner
  } else {
    model$data$tables <- rbind(
      model$data$tables,
      data.frame(table = tbl_name, owner = owner, stringsAsFactors = FALSE)
    )
  }
  model
}

#' Normalize data input to a database table reference
#'
#' Accepts a data.frame, a dbplyr `tbl_lazy`, or a character table name
#' and returns a standardized list describing the data's location in the
#' database. For data.frames, uploads via `dbWriteTable`. For database
#' references, materializes a table to inject `unique_id` if missing.
#'
#' @param data A data.frame, `tbl_lazy`, or character table name.
#' @param con A DBI connection (optional when `data` is `tbl_lazy`).
#' @param tbl_name Internal table/view name to create.
#' @param add_unique_id Logical. If TRUE, injects a `unique_id` column
#'   when one is not already present.
#' @return A list with `tbl_name`, `con`, `n_records`, `columns`, and
#'   `needs_cleanup` (logical).
#' @noRd
register_data <- function(
  data,
  con = NULL,
  tbl_name = '__il_data',
  add_unique_id = TRUE
) {
  # ---- tbl_lazy (dbplyr lazy table reference) ----
  if (inherits(data, 'tbl_lazy')) {
    rlang::check_installed(
      'dbplyr',
      reason = 'to use database table references.'
    )
    remote_con <- dbplyr::remote_con(data)
    con <- con %||% remote_con
    cols <- colnames(data)

    # Count records in-database
    n_records <- count_tbl_lazy(data, con)

    if (n_records == 0L) {
      cli::cli_abort('Cannot register a zero-row table.')
    }

    # Determine the source SQL
    remote_nm <- dbplyr::remote_name(data)
    source_sql <- dbplyr::remote_query(data)
    if (!is.null(remote_nm)) {
      source_sql <- glue::glue('SELECT * FROM {sql_quote_identifier(remote_nm)}')
    }

    # Create a registered object, adding unique_id if needed.
    # When we must synthesize row IDs, materialize them once in a table so
    # they stay stable across later queries to the model.
    # Drop any existing table/view first to avoid type conflicts.
    drop_registered(con, tbl_name)
    qtbl_name <- sql_quote_identifier(tbl_name)
    has_uid <- 'unique_id' %in% cols
    if (has_uid) {
      view_sql <- glue::glue(
        'CREATE VIEW {qtbl_name} AS {source_sql}'
      )
      DBI::dbExecute(con, view_sql)
    } else if (add_unique_id) {
      table_sql <- glue::glue(
        'CREATE TABLE {qtbl_name} AS ',
        'SELECT *, ROW_NUMBER() OVER () AS unique_id FROM ({source_sql}) AS __src'
      )
      cols <- c(cols, 'unique_id')
      DBI::dbExecute(con, table_sql)
    } else {
      view_sql <- glue::glue(
        'CREATE VIEW {qtbl_name} AS {source_sql}'
      )
      DBI::dbExecute(con, view_sql)
    }
    if ('unique_id' %in% cols) {
      validate_registered_unique_id(con, tbl_name, cols)
    }

    return(list(
      tbl_name = tbl_name,
      con = con,
      n_records = n_records,
      columns = cols,
      column_classes = infer_registered_column_classes(con, tbl_name),
      needs_cleanup = TRUE
    ))
  }

  # ---- character string (existing table name) ----
  if (is.character(data) && length(data) == 1L) {
    if (is.null(con)) {
      cli::cli_abort(
        'A DBI connection ({.arg con}) is required when {.arg data} is a table name.'
      )
    }

    cols <- DBI::dbListFields(con, data)
    qdata <- sql_quote_identifier(data)
    n_records <- as.integer(
      DBI::dbGetQuery(con, glue::glue('SELECT COUNT(*) AS n FROM {qdata}'))$n[1]
    )

    if (n_records == 0L) {
      cli::cli_abort('Cannot register a zero-row table.')
    }

    has_uid <- 'unique_id' %in% cols
    # Drop any existing table/view first to avoid type conflicts.
    # As above, materialize synthesized row IDs once so they stay stable.
    drop_registered(con, tbl_name)
    qtbl_name <- sql_quote_identifier(tbl_name)
    if (has_uid) {
      view_sql <- glue::glue(
        'CREATE VIEW {qtbl_name} AS SELECT * FROM {qdata}'
      )
      DBI::dbExecute(con, view_sql)
    } else if (add_unique_id) {
      table_sql <- glue::glue(
        'CREATE TABLE {qtbl_name} AS ',
        'SELECT *, ROW_NUMBER() OVER () AS unique_id FROM {qdata}'
      )
      cols <- c(cols, 'unique_id')
      DBI::dbExecute(con, table_sql)
    } else {
      view_sql <- glue::glue(
        'CREATE VIEW {qtbl_name} AS SELECT * FROM {qdata}'
      )
      DBI::dbExecute(con, view_sql)
    }
    if ('unique_id' %in% cols) {
      validate_registered_unique_id(con, tbl_name, cols)
    }

    return(list(
      tbl_name = tbl_name,
      con = con,
      n_records = n_records,
      columns = cols,
      column_classes = infer_registered_column_classes(con, tbl_name),
      needs_cleanup = TRUE
    ))
  }

  # ---- data.frame / tibble (in-memory) ----
  if (is.data.frame(data)) {
    if (is.null(con)) {
      cli::cli_abort(
        'A DBI connection ({.arg con}) is required when {.arg data} is a data frame.'
      )
    }

    if (nrow(data) == 0L) {
      cli::cli_abort('Cannot register a zero-row data frame.')
    }

    data <- factor_to_char(data)
    if (add_unique_id && !('unique_id' %in% names(data))) {
      data$unique_id <- seq_len(nrow(data))
    }
    if ('unique_id' %in% names(data)) {
      validate_data_frame_unique_id(data)
    }
    column_classes <- infer_column_classes(data)
    data <- as.data.frame(data)
    DBI::dbWriteTable(con, tbl_name, data, overwrite = TRUE)

    return(list(
      tbl_name = tbl_name,
      con = con,
      n_records = nrow(data),
      columns = names(data),
      column_classes = column_classes,
      needs_cleanup = TRUE
    ))
  }

  cli::cli_abort(
    '{.arg data} must be a data frame, a {.cls tbl_lazy} reference, or a table name string.'
  )
}

#' Count rows in a tbl_lazy without collecting
#' @param tbl A tbl_lazy object.
#' @param con A DBI connection.
#' @return Integer row count.
#' @noRd
count_tbl_lazy <- function(tbl, con) {
  remote_nm <- dbplyr::remote_name(tbl)
  if (!is.null(remote_nm)) {
    sql <- glue::glue(
      'SELECT COUNT(*) AS n FROM {sql_quote_identifier(remote_nm)}'
    )
  } else {
    inner <- dbplyr::remote_query(tbl)
    sql <- glue::glue('SELECT COUNT(*) AS n FROM ({inner}) AS __cnt')
  }
  as.integer(DBI::dbGetQuery(con, sql)$n[1])
}

#' Drop a view or table created by register_data
#' @param con A DBI connection.
#' @param tbl_name The name of the view/table to drop.
#' @noRd
drop_registered <- function(con, tbl_name) {
  qtbl_name <- sql_quote_identifier(tbl_name)
  try(
    DBI::dbExecute(con, glue::glue('DROP VIEW IF EXISTS {qtbl_name}')),
    silent = TRUE
  )
  try(DBI::dbRemoveTable(con, tbl_name, fail_if_missing = FALSE), silent = TRUE)
}

#' Validate unique_id in an in-memory data frame
#' @param data A data frame.
#' @noRd
validate_data_frame_unique_id <- function(data) {
  if (anyNA(data$unique_id)) {
    cli::cli_abort('{.field unique_id} must not contain missing values.')
  }
  if (anyDuplicated(data$unique_id) > 0L) {
    cli::cli_abort('{.field unique_id} must uniquely identify rows.')
  }
  invisible(NULL)
}

#' Validate unique_id in a registered database table or view
#' @param con A DBI connection.
#' @param tbl_name Registered table/view name.
#' @param columns Registered column names.
#' @noRd
validate_registered_unique_id <- function(con, tbl_name, columns) {
  qtbl_name <- sql_quote_identifier(tbl_name)
  res <- DBI::dbGetQuery(
    con,
    glue::glue(
      'SELECT COUNT(*) AS n, ',
      'SUM(CASE WHEN unique_id IS NULL THEN 1 ELSE 0 END) AS n_missing, ',
      'COUNT(DISTINCT unique_id) AS n_distinct ',
      'FROM {qtbl_name}'
    )
  )
  if (as.numeric(res$n_missing[1]) > 0) {
    cli::cli_abort('{.field unique_id} must not contain missing values.')
  }
  if (as.numeric(res$n_distinct[1]) != as.numeric(res$n[1])) {
    cli::cli_abort('{.field unique_id} must uniquely identify rows.')
  }
  invisible(NULL)
}
