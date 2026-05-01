#' Save a Model to Disk
#'
#' Serialises a trained `il_model` object to `.json` or `.rds`, chosen from
#' `path`.
#'
#' `.json` writes Splink settings JSON. Other extensions write RDS. The
#' database connection and any in-database tables are not stored; supply a
#' fresh connection with [il_attach()] after loading.
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

  format <- detect_model_serialization_format(path)
  if (identical(format, 'json')) {
    if (identical(model$params$estimator_mode, 'dependency-aware')) {
      cli::cli_abort(
        'Dependency-aware estimator state cannot be saved as Splink settings JSON. Use an {.file .rds} path.'
      )
    }
    write_model_json(model, path)
  } else {
    saveRDS(model_to_rds_payload(model), path)
  }

  invisible(model)
}

#' Load a Saved Model
#'
#' Reads a saved `il_model` object from `.json` or `.rds`.
#'
#' Settings JSON is loaded into an `il_model` that can be used with
#' [il_attach()] and [predict()]. The database connection and any in-database
#' tables are not loaded.
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

  format <- detect_model_serialization_format(path)
  if (identical(format, 'json')) {
    check_jsonlite_installed()
    raw <- jsonlite::read_json(path, simplifyVector = FALSE)
    return(load_json_model(raw))
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

detect_model_serialization_format <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, 'json')) 'json' else 'rds'
}

check_jsonlite_installed <- function() {
  rlang::check_installed(
    'jsonlite',
    reason = 'to read or write `.json` model files.'
  )
}

model_to_rds_payload <- function(model) {
  list(
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
}

write_model_json <- function(model, path) {
  check_jsonlite_installed()
  settings <- model_to_json_settings(model)
  jsonlite::write_json(
    settings,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = 'null',
    digits = NA
  )
}

model_to_json_settings <- function(model) {
  dialect <- model_json_dialect(model)
  params <- model$params
  if (!is.null(params$comparisons) &&
    'level' %in% names(params$comparisons) &&
    !'gamma_level' %in% names(params$comparisons)) {
    params$comparisons <- migrate_params_to_gamma_level(params$comparisons)
  }

  list(
    link_type = irelink_to_splink_link_type(model$link_type %||% 'dedupe'),
    probability_two_random_records_match = safe_prior(model),
    em_convergence = 0.0001,
    max_iterations = 25L,
    retain_matching_columns = TRUE,
    retain_intermediate_calculation_columns = FALSE,
    additional_columns_to_retain = list(),
    unique_id_column_name = 'unique_id',
    source_dataset_column_name = 'source_dataset',
    comparison_vector_value_column_prefix = 'gamma_',
    sql_dialect = dialect,
    blocking_rules_to_generate_predictions = lapply(
      model$spec$blocking_rules,
      blocking_rule_to_json_settings,
      dialect = dialect
    ),
    comparisons = lapply(
      model$spec$comparisons,
      comparison_to_json_settings,
      params = params$comparisons,
      dialect = dialect
    )
  )
}

model_json_dialect <- function(model) {
  if (is.null(model$con)) {
    return('duckdb')
  }
  dialect <- detect_dialect(model$con)
  if (identical(dialect, 'generic')) 'duckdb' else dialect
}

irelink_to_splink_link_type <- function(link_type) {
  switch(link_type,
    'dedupe' = 'dedupe_only',
    'link' = 'link_only',
    'link_and_dedupe' = 'link_and_dedupe',
    'dedupe_only'
  )
}

splink_to_irelink_link_type <- function(link_type) {
  switch(link_type %||% 'dedupe_only',
    'dedupe_only' = 'dedupe',
    'link_only' = 'link',
    'link_and_dedupe' = 'link_and_dedupe',
    'dedupe'
  )
}

blocking_rule_to_json_settings <- function(rule, dialect) {
  sql <- build_blocking_condition(
    rule$columns,
    rule$where,
    transform = rule$transform,
    dialect = dialect
  )
  list(
    blocking_rule = table_alias_sql_to_splink(sql),
    sql_dialect = dialect
  )
}

comparison_to_json_settings <- function(comp, params, dialect) {
  list(
    output_column_name = comp$columns,
    comparison_levels = comparison_levels_to_json_settings(comp, params, dialect)
  )
}

comparison_levels_to_json_settings <- function(comp, params, dialect) {
  levels <- levels_for_json_export(comp$method)
  explicit_levels <- Filter(function(level) {
    !isTRUE(level$is_null_level) && !isTRUE(level$is_else_level)
  }, levels)
  n_explicit <- length(explicit_levels)
  explicit_index <- 0L

  lapply(levels, function(level) {
    out <- list(
      sql_condition = splink_sql_condition(level, comp$columns, dialect, comp$transform),
      fix_m_probability = FALSE,
      fix_u_probability = FALSE
    )

    gamma_level <- NULL
    if (isTRUE(level$is_null_level)) {
      out$is_null_level <- TRUE
    } else if (isTRUE(level$is_else_level)) {
      gamma_level <- 0L
    } else {
      explicit_index <<- explicit_index + 1L
      gamma_level <- n_explicit - explicit_index + 1L
    }

    param_row <- matching_param_row(params, comp$columns, gamma_level)
    if (!is.null(param_row)) {
      out$m_probability <- as.numeric(param_row$m[[1]])
      out$u_probability <- as.numeric(param_row$u[[1]])
    }

    if (!is.null(gamma_level) &&
      gamma_level == n_explicit &&
      isTRUE(comp$method$term_frequency)) {
      out$tf_adjustment_column <- comp$columns
      if (!is.null(comp$tf_minimum_u_value) &&
        !identical(comp$tf_minimum_u_value, 0)) {
        out$tf_minimum_u_value <- comp$tf_minimum_u_value
      }
      if (!is.null(comp$tf_adjustment_weight) &&
        !identical(comp$tf_adjustment_weight, 1)) {
        out$tf_adjustment_weight <- comp$tf_adjustment_weight
      }
    }

    out
  })
}

levels_for_json_export <- function(method) {
  method_name <- method$method
  if (identical(method_name, 'levels')) {
    levels <- method$levels
    has_else <- any(vapply(levels, function(level) {
      isTRUE(level$is_else_level)
    }, logical(1)))
    if (!has_else) {
      levels <- c(levels, list(cl_else()))
    }
    return(levels)
  }

  explicit_levels <- if (!is.null(method$thresholds)) {
    lapply(seq_along(method$thresholds), function(i) {
      fields <- list()
      if (!is.null(method$thresholds)) {
        fields$thresholds <- method$thresholds[i]
      }
      if (!is.null(method$units)) {
        fields$units <- method$units[i]
      }
      if (!is.null(method$fn)) {
        fields$fn <- method$fn
      }
      do.call(
        new_comparison_level,
        c(list(method_name), fields)
      )
    })
  } else {
    list(method)
  }

  c(explicit_levels, list(cl_else()))
}

splink_sql_condition <- function(level, col, dialect, transform = NULL) {
  if (isTRUE(level$is_null_level)) {
    return(paste0(col, '_l IS NULL OR ', col, '_r IS NULL'))
  }
  if (isTRUE(level$is_else_level)) {
    return('ELSE')
  }

  null_guard <- paste0(col, '_l IS NOT NULL AND ', col, '_r IS NOT NULL')
  lcol <- sql_transform_col(paste0(col, '_l'), transform, dialect)
  rcol <- sql_transform_col(paste0(col, '_r'), transform, dialect)

  sql <- sql_sublevel_condition(level, col, dialect, null_guard, lcol, rcol)
  table_alias_sql_to_splink(sql)
}

matching_param_row <- function(params, comparison, gamma_level) {
  if (is.null(params) || is.null(gamma_level)) {
    return(NULL)
  }
  rows <- params[
    params$comparison == comparison &
      params$gamma_level == gamma_level, ,
    drop = FALSE
  ]
  if (nrow(rows) == 0L) {
    return(NULL)
  }
  rows
}

table_alias_sql_to_splink <- function(sql) {
  sql <- gsub('\\bl\\.([A-Za-z][A-Za-z0-9_]*)\\b', '\\1_l', sql, perl = TRUE)
  gsub('\\br\\.([A-Za-z][A-Za-z0-9_]*)\\b', '\\1_r', sql, perl = TRUE)
}

splink_sql_to_table_alias_sql <- function(sql) {
  sql <- gsub('\\b([A-Za-z][A-Za-z0-9_]*)_l\\b', 'l.\\1', sql, perl = TRUE)
  gsub('\\b([A-Za-z][A-Za-z0-9_]*)_r\\b', 'r.\\1', sql, perl = TRUE)
}

load_json_model <- function(raw) {
  comparisons <- lapply(raw$comparisons %||% list(), splink_json_to_comparison)
  blocking_rules <- lapply(
    raw$blocking_rules_to_generate_predictions %||% list(),
    splink_json_to_blocking_rule
  )
  spec <- new_il_spec(comparisons = comparisons, blocking_rules = blocking_rules)
  params <- splink_json_to_params(
    raw$comparisons %||% list(),
    raw$probability_two_random_records_match
  )
  trained <- !is.null(params$comparisons) &&
    nrow(params$comparisons) > 0L &&
    !anyNA(params$comparisons$m) &&
    !anyNA(params$comparisons$u)

  new_il_model(
    spec = spec,
    data = list(
      columns = unique(get_spec_columns(spec))
    ),
    con = NULL,
    link_type = splink_to_irelink_link_type(raw$link_type),
    params = params,
    trained = trained
  )
}

splink_json_to_comparison <- function(cmp_data) {
  levels <- splink_json_levels_to_irelink(
    cmp_data$comparison_levels %||% list(),
    cmp_data$output_column_name
  )
  tf_level <- highest_tf_level(cmp_data$comparison_levels %||% list())

  list(
    columns = cmp_data$output_column_name,
    method = new_comparison_level(
      'levels',
      levels = levels,
      term_frequency = !is.null(tf_level)
    ),
    transform = NULL,
    tf_adjustment_weight = tf_level$tf_adjustment_weight %||% 1.0,
    tf_minimum_u_value = tf_level$tf_minimum_u_value %||% 0.0
  )
}

splink_json_levels_to_irelink <- function(levels, col) {
  irelink_levels <- lapply(levels, function(level) {
    cond <- trimws(level$sql_condition %||% '')
    if (isTRUE(level$is_null_level) || isTRUE(level$null_level)) {
      return(cl_null())
    }
    if (identical(toupper(cond), 'ELSE')) {
      return(cl_else())
    }

    cond_sql <- splink_sql_to_table_alias_sql(cond)
    if (grepl(
      paste0(
        '^', col, '_l\\s+IS\\s+NULL\\s+OR\\s+',
        col, '_r\\s+IS\\s+NULL$'
      ),
      cond,
      ignore.case = TRUE,
      perl = TRUE
    )) {
      return(cl_null())
    }

    cl_custom(cond_sql)
  })

  has_else <- any(vapply(irelink_levels, function(level) {
    isTRUE(level$is_else_level)
  }, logical(1)))
  if (!has_else) {
    irelink_levels <- c(irelink_levels, list(cl_else()))
  }

  irelink_levels
}

highest_tf_level <- function(levels) {
  tf_levels <- Filter(function(level) {
    !is.null(level$tf_adjustment_column)
  }, levels)
  if (length(tf_levels) == 0L) {
    return(NULL)
  }
  tf_levels[[1]]
}

splink_json_to_blocking_rule <- function(br_data) {
  sql <- if (is.character(br_data)) br_data else br_data$blocking_rule
  sql <- trimws(splink_sql_to_table_alias_sql(sql))
  structure(
    parse_blocking_sql(sql),
    class = 'il_blocking_rule'
  )
}

parse_blocking_sql <- function(sql) {
  if (!nzchar(sql)) {
    return(list(columns = character(0), where = NULL, transform = NULL, explode = NULL))
  }

  parts <- strsplit(sql, '\\s+AND\\s+', perl = TRUE)[[1]]
  columns <- character(0)
  where_parts <- character(0)

  for (part in parts) {
    part <- trimws(part)
    match <- regexec('^l\\.([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*r\\.\\1$', part, perl = TRUE)
    captures <- regmatches(part, match)[[1]]
    if (length(captures) > 1L) {
      columns <- c(columns, captures[2])
    } else {
      where_parts <- c(where_parts, part)
    }
  }

  list(
    columns = columns,
    where = if (length(where_parts) > 0L) paste(where_parts, collapse = ' AND ') else NULL,
    transform = NULL,
    explode = NULL
  )
}

splink_json_to_params <- function(comparisons, prior = NULL) {
  rows <- list()

  for (cmp_data in comparisons) {
    levels <- cmp_data$comparison_levels %||% list()
    explicit_levels <- Filter(function(level) {
      cond <- trimws(level$sql_condition %||% '')
      !isTRUE(level$is_null_level) &&
        !isTRUE(level$null_level) &&
        !identical(toupper(cond), 'ELSE')
    }, levels)
    n_explicit <- length(explicit_levels)
    explicit_index <- 0L

    for (level in levels) {
      cond <- trimws(level$sql_condition %||% '')
      if (isTRUE(level$is_null_level) || isTRUE(level$null_level)) {
        next
      }

      gamma_level <- if (identical(toupper(cond), 'ELSE')) {
        0L
      } else {
        explicit_index <- explicit_index + 1L
        n_explicit - explicit_index + 1L
      }

      if (is.null(level$m_probability) || is.null(level$u_probability)) {
        next
      }

      rows[[length(rows) + 1L]] <- tibble::tibble(
        comparison = cmp_data$output_column_name,
        gamma_level = as.integer(gamma_level),
        m = as.numeric(level$m_probability),
        u = as.numeric(level$u_probability)
      )
    }
  }

  out <- list()
  if (length(rows) > 0L) {
    out$comparisons <- do.call(rbind, rows)
    out$comparisons <- out$comparisons[
      order(out$comparisons$comparison, out$comparisons$gamma_level), ,
      drop = FALSE
    ]
  }
  if (!is.null(prior) && length(prior) == 1L) {
    out$prior <- prior
  }
  out
}
