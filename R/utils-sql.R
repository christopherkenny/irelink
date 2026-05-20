# Internal SQL generation functions for comparison levels, blocking rules,
# and join conditions. Not exported.

#' Convert a time-diff threshold + unit to total seconds
#' @param value Numeric threshold value.
#' @param unit Character unit (seconds, minutes, hours, days, months, years).
#' @return Numeric value in seconds.
#' @noRd
time_diff_to_seconds <- function(value, unit) {
  mult <- switch(
    unit,
    'seconds' = 1,
    'minutes' = 60,
    'hours' = 3600,
    'days' = 86400,
    'months' = 86400 * 30,
    'years' = 86400 * 365,
    1
  )
  value * mult
}

#' Detect the SQL dialect from a DBI connection
#' @param con A DBI connection object.
#' @return A character string: "duckdb", "sqlite", or "generic".
#' @noRd
detect_dialect <- function(con) {
  cls <- tolower(paste(class(con), collapse = ' '))
  if (grepl('duckdb', cls)) {
    return('duckdb')
  }
  if (grepl('sqlite', cls)) {
    return('sqlite')
  }
  if (grepl('postgres', cls)) {
    return('postgres')
  }
  'generic'
}

#' Can this dialect compute fuzzy string comparisons in SQL?
#' @noRd
dialect_has_fuzzy_sql <- function(dialect) {
  dialect %in% c('duckdb', 'postgres')
}

#' Quote a SQL identifier with ANSI double quotes
#' @noRd
sql_quote_identifier <- function(x) {
  if (!is.character(x) || anyNA(x)) {
    cli::cli_abort('SQL identifiers must be non-missing character strings.')
  }
  vapply(
    x,
    function(val) {
      paste0('"', gsub('"', '""', val, fixed = TRUE), '"')
    },
    character(1),
    USE.NAMES = FALSE
  )
}

#' Build an aliased column reference
#' @noRd
sql_col_ref <- function(alias, col) {
  paste0(alias, '.', sql_quote_identifier(col))
}

#' Join identifiers for a SELECT or GROUP BY clause
#' @noRd
sql_identifier_csv <- function(x) {
  paste(sql_quote_identifier(x), collapse = ', ')
}

#' Build a dialect-specific date-difference expression in days
#' @noRd
sql_date_diff_expr <- function(lcol, rcol, dialect) {
  if (identical(dialect, 'duckdb')) {
    return(glue::glue(
      'ABS(TRY_CAST({lcol} AS DATE) - TRY_CAST({rcol} AS DATE))'
    ))
  }
  if (identical(dialect, 'postgres')) {
    return(glue::glue('ABS(CAST({lcol} AS DATE) - CAST({rcol} AS DATE))'))
  }
  glue::glue('ABS(JULIANDAY({lcol}) - JULIANDAY({rcol}))')
}

#' Build a dialect-specific timestamp-difference expression in seconds
#' @noRd
sql_time_diff_expr <- function(lcol, rcol, dialect) {
  if (identical(dialect, 'duckdb')) {
    return(glue::glue(
      'ABS(EPOCH(CAST({lcol} AS TIMESTAMP)) - EPOCH(CAST({rcol} AS TIMESTAMP)))'
    ))
  }
  if (identical(dialect, 'postgres')) {
    return(glue::glue(
      'ABS(EXTRACT(EPOCH FROM (CAST({lcol} AS TIMESTAMP) - CAST({rcol} AS TIMESTAMP))))'
    ))
  }
  glue::glue(
    'ABS((JULIANDAY({lcol}) - JULIANDAY({rcol})) * 86400.0)'
  )
}

#' Wrap a column reference with a SQL-translated transform
#'
#' Maps common R functions (tolower, toupper, trimws) and phonetic
#' transforms ([il_soundex], [il_metaphone], [il_dmetaphone]) to their
#' SQL equivalents. Returns the column reference unchanged when the
#' transform is `NULL` or has no known SQL translation.
#'
#' @param col_ref Character SQL column reference (e.g. `"l.name"`).
#' @param transform An R function or `NULL`.
#' @param dialect Optional SQL dialect string for phonetic transforms.
#' @return A SQL expression string.
#' @noRd
sql_transform_col <- function(col_ref, transform, dialect = NULL) {
  if (is.null(transform)) {
    return(col_ref)
  }
  # Transform chains: apply each step, nesting inside-out
  if (is_transform_chain(transform)) {
    fns <- attr(transform, 'transforms')
    result <- col_ref
    for (fn in fns) {
      result <- sql_transform_col(result, fn, dialect)
    }
    return(result)
  }
  # Parameterized column transforms (il_substr, il_nullif, etc.)
  if (is_column_transform(transform)) {
    return(column_transform_sql(transform, col_ref, dialect))
  }
  # Phonetic transforms need special handling (dialect-dependent, some
  # have multi-arg SQL signatures)
  phonetic_sql <- phonetic_transform_sql(transform, col_ref, dialect)
  if (!is.null(phonetic_sql)) {
    return(phonetic_sql)
  }
  fn_name <- transform_to_sql_fn(transform)
  if (is.null(fn_name)) {
    cli::cli_abort(
      c(
        'Transform function cannot be translated to SQL.',
        'i' = 'Use a built-in SQL-capable transform or run through an R fallback path.'
      ),
      class = 'il_error_type'
    )
  }
  paste0(fn_name, '(', col_ref, ')')
}

#' Map an R function to its SQL equivalent name
#' @noRd
transform_to_sql_fn <- function(transform) {
  if (identical(transform, tolower)) {
    return('LOWER')
  }
  if (identical(transform, toupper)) {
    return('UPPER')
  }
  if (identical(transform, trimws)) {
    return('TRIM')
  }
  NULL
}


#' Map an R function (or named list of functions) to a serializable name
#' @noRd
transform_to_name <- function(transform) {
  if (is.list(transform)) {
    parts <- vapply(
      names(transform),
      function(nm) {
        paste0(nm, ': ', transform_to_name(transform[[nm]]))
      },
      character(1)
    )
    return(paste(parts, collapse = ', '))
  }
  if (is_transform_chain(transform)) {
    names <- vapply(
      attr(transform, 'transforms'),
      transform_to_name,
      character(1)
    )
    if (anyNA(names)) {
      cli::cli_warn(
        'Custom transform in chain cannot be serialized; it will be lost on save/load.'
      )
      return(NA_character_)
    }
    return(paste(names, collapse = ' -> '))
  }
  if (identical(transform, tolower)) {
    return('tolower')
  }
  if (identical(transform, toupper)) {
    return('toupper')
  }
  if (identical(transform, trimws)) {
    return('trimws')
  }
  if (identical(transform, il_soundex)) {
    return('il_soundex')
  }
  if (identical(transform, il_metaphone)) {
    return('il_metaphone')
  }
  if (identical(transform, il_dmetaphone)) {
    return('il_dmetaphone')
  }
  if (is_column_transform(transform)) {
    return(column_transform_to_name(transform))
  }
  cli::cli_warn(
    'Custom transform cannot be serialized; it will be lost on save/load.'
  )
  NULL
}

#' Validate the .transform argument for il_block_on / block_on
#' @noRd
validate_transform_arg <- function(transform) {
  if (is.null(transform) || is.function(transform)) {
    return(invisible(NULL))
  }
  if (is.list(transform)) {
    if (is.null(names(transform)) || !all(nzchar(names(transform)))) {
      cli::cli_abort(
        '{.arg .transform} list must be fully named (one name per column transform).',
        class = 'il_error_type'
      )
    }
    bad <- !vapply(transform, is.function, logical(1))
    if (any(bad)) {
      cli::cli_abort(
        'All entries in {.arg .transform} list must be functions.',
        class = 'il_error_type'
      )
    }
    return(invisible(NULL))
  }
  cli::cli_abort(
    paste0(
      '{.arg .transform} must be a function, a named list of functions, ',
      'or {.code NULL}, not {.obj_type_friendly {(transform)}}.'
    ),
    class = 'il_error_type'
  )
}

#' Is this a phonetic transform function?
#' @noRd
is_phonetic_transform <- function(transform) {
  identical(transform, il_soundex) ||
    identical(transform, il_metaphone) ||
    identical(transform, il_dmetaphone)
}

#' Generate SQL expression for a phonetic transform
#'
#' Returns the dialect-appropriate SQL wrapping `col_ref`, or `NULL` if
#' `transform` is not a phonetic function.
#'
#' @param transform An R function.
#' @param col_ref Character SQL column reference.
#' @param dialect Optional SQL dialect string.
#' @return A SQL expression string, or `NULL`.
#' @noRd
phonetic_transform_sql <- function(transform, col_ref, dialect = NULL) {
  if (identical(transform, il_soundex)) {
    if (!is.null(dialect)) {
      validate_phonetic_dialect('il_soundex', dialect)
    }
    # DuckDB uses our registered macro; PostgreSQL has native soundex()
    if (identical(dialect, 'duckdb')) {
      return(paste0('il_soundex(', col_ref, ')'))
    }
    return(paste0('soundex(', col_ref, ')'))
  }
  if (identical(transform, il_metaphone)) {
    if (!is.null(dialect)) {
      validate_phonetic_dialect('il_metaphone', dialect)
    }
    return(paste0('metaphone(', col_ref, ', 10)'))
  }
  if (identical(transform, il_dmetaphone)) {
    if (!is.null(dialect)) {
      validate_phonetic_dialect('il_dmetaphone', dialect)
    }
    return(paste0('dmetaphone(', col_ref, ')'))
  }
  NULL
}

#' Validate that a phonetic function is supported by a SQL dialect
#' @noRd
validate_phonetic_dialect <- function(fn_name, dialect) {
  supported <- switch(
    fn_name,
    'il_soundex' = c('duckdb', 'postgres'),
    'il_metaphone' = 'postgres',
    'il_dmetaphone' = 'postgres',
    character(0)
  )
  if (!dialect %in% supported) {
    label <- switch(
      fn_name,
      'il_soundex' = 'Soundex',
      'il_metaphone' = 'Metaphone',
      'il_dmetaphone' = 'Double Metaphone'
    )
    cli::cli_abort(c(
      '{label} is not available for the {.val {dialect}} backend.',
      'i' = 'Supported backend{?s}: {.val {supported}}.'
    ))
  }
}

#' Generate a multi-level gamma CASE expression for one comparison
#'
#' Used to push gamma computation into SQL for backends that support
#' string similarity functions (DuckDB, PostgreSQL). Returns integer
#' gamma codes: 0 (else) through K (best match), where K depends on
#' the number of thresholds.
#'
#' @param comp A comparison entry from the spec (with $columns, $method).
#' @param dialect SQL dialect string.
#' @return A SQL expression that evaluates to an integer gamma code.
#' @noRd
sql_gamma_case <- function(comp, dialect) {
  col <- comp$columns
  level <- comp$method
  method <- level$method
  thresholds <- level$thresholds
  tf <- comp$transform

  if (length(col) == 2L && method != 'geo_distance') {
    cli::cli_abort(
      'Only {.fn cl_geo_distance} comparisons can use two columns.'
    )
  }

  # Build column references with optional transforms
  if (length(col) == 1L) {
    lref <- sql_col_ref('l', col)
    rref <- sql_col_ref('r', col)
    lcol <- sql_transform_col(lref, tf, dialect)
    rcol <- sql_transform_col(rref, tf, dialect)
    null_guard <- glue::glue('{lref} IS NOT NULL AND {rref} IS NOT NULL')
  }

  if (method == 'exact') {
    return(glue::glue(
      'CASE WHEN {null_guard} AND {lcol} = {rcol} THEN 1 ELSE 0 END'
    ))
  }

  # Build multi-level CASE for similarity methods with thresholds.
  # Thresholds are stored strictest-first (descending for similarity,
  # ascending for distance). The SQL CASE evaluates top-to-bottom,
  # returning the first match — so strictest threshold gets highest gamma.

  if (method == 'jaro_winkler') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND jaro_winkler_similarity({lcol}, {rcol}) >= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'jaro') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND jaro_similarity({lcol}, {rcol}) >= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'jaccard') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND jaccard({lcol}, {rcol}) >= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'cosine') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND cosine_similarity({lcol}, {rcol}) >= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'levenshtein') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND levenshtein({lcol}, {rcol}) <= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'damerau_levenshtein') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND damerau_levenshtein({lcol}, {rcol}) <= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'numeric_diff') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) <= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'pct_diff') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) / ',
          'NULLIF(GREATEST(ABS(CAST({lcol} AS DOUBLE)), ABS(CAST({rcol} AS DOUBLE))), 0) < {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'date_diff') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        mult <- switch(
          level$units[i],
          'days' = 1,
          'months' = 30,
          'years' = 365,
          1
        )
        days_val <- thresholds[i] * mult
        diff_expr <- sql_date_diff_expr(lcol, rcol, dialect)
        glue::glue(
          'WHEN {null_guard} AND {diff_expr} <= {days_val} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'time_diff') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        secs_val <- time_diff_to_seconds(thresholds[i], level$units[i])
        diff_expr <- sql_time_diff_expr(lcol, rcol, dialect)
        glue::glue(
          'WHEN {null_guard} AND {diff_expr} <= {secs_val} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'soundex') {
    soundex_fn <- if (identical(dialect, 'duckdb')) 'il_soundex' else 'soundex'
    return(glue::glue(
      'CASE WHEN {null_guard} AND {soundex_fn}({lcol}) = {soundex_fn}({rcol}) THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'geo_distance') {
    if (length(col) != 2L) {
      cli::cli_abort(
        '{.fn cl_geo_distance} comparisons require latitude and longitude columns.'
      )
    }
    lat_l <- sql_transform_col(sql_col_ref('l', col[1]), tf, dialect)
    lon_l <- sql_transform_col(sql_col_ref('l', col[2]), tf, dialect)
    lat_r <- sql_transform_col(sql_col_ref('r', col[1]), tf, dialect)
    lon_r <- sql_transform_col(sql_col_ref('r', col[2]), tf, dialect)
    null_guard2 <- glue::glue(
      '{sql_col_ref("l", col[1])} IS NOT NULL AND {sql_col_ref("r", col[1])} IS NOT NULL ',
      'AND {sql_col_ref("l", col[2])} IS NOT NULL AND {sql_col_ref("r", col[2])} IS NOT NULL'
    )
    dist <- glue::glue(
      '2 * 6371 * ASIN(SQRT(POWER(SIN(RADIANS(({lat_r} - {lat_l}) / 2)), 2) + ',
      'COS(RADIANS({lat_l})) * COS(RADIANS({lat_r})) * ',
      'POWER(SIN(RADIANS(({lon_r} - {lon_l}) / 2)), 2)))'
    )
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard2} AND {dist} <= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'array_intersect') {
    n <- length(thresholds)
    whens <- vapply(
      seq_along(thresholds),
      function(i) {
        glue::glue(
          'WHEN {null_guard} AND ARRAY_LENGTH(ARRAY_INTERSECT({lcol}, {rcol})) >= {thresholds[i]} THEN {n - i + 1L}'
        )
      },
      character(1)
    )
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'array_subset') {
    return(glue::glue(
      'CASE WHEN {null_guard} AND ARRAY_LENGTH(ARRAY_INTERSECT({lcol}, {rcol})) = ',
      'LEAST(ARRAY_LENGTH({lcol}), ARRAY_LENGTH({rcol})) THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'custom') {
    sql_expr <- glue::glue(
      level$sql_expr,
      col = sql_quote_identifier(col[[1]]),
      .open = '{',
      .close = '}'
    )
    return(glue::glue(
      'CASE WHEN {null_guard} AND ({sql_expr}) THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'array_min_distance') {
    return(sql_array_min_distance_case(level, col, null_guard))
  }

  if (method == 'levels') {
    has_null_level <- any(vapply(
      level$levels,
      function(l) {
        isTRUE(l$is_null_level)
      },
      logical(1)
    ))

    # Build multi-level CASE from sublevels (skip null and else)
    sublevels <- Filter(
      function(l) {
        !isTRUE(l$is_null_level) && !isTRUE(l$is_else_level)
      },
      level$levels
    )
    n <- length(sublevels)
    null_when <- if (has_null_level) {
      glue::glue('WHEN NOT ({null_guard}) THEN -1 ')
    } else {
      ''
    }
    if (n == 0L) {
      return(glue::glue(
        'CASE {null_when}WHEN {null_guard} AND {lcol} = {rcol} THEN 1 ELSE 0 END'
      ))
    }
    whens <- vapply(
      seq_along(sublevels),
      function(i) {
        sub <- sublevels[[i]]
        cond <- sql_sublevel_condition(
          sub,
          col,
          dialect,
          null_guard,
          lcol,
          rcol
        )
        glue::glue('WHEN {cond} THEN {n - i + 1L}')
      },
      character(1)
    )
    return(glue::glue(
      'CASE {null_when}{paste(whens, collapse = " ")} ELSE 0 END'
    ))
  }

  # Fallback: exact match
  glue::glue(
    'CASE WHEN {null_guard} AND {lcol} = {rcol} THEN 1 ELSE 0 END'
  )
}

#' Generate a SQL condition for a single sublevel within cl_levels()
#' @param sub An il_comparison_level sublevel object.
#' @param col Column name (for fallback references).
#' @param dialect SQL dialect string.
#' @param null_guard SQL null guard clause.
#' @param lcol Transformed left column reference.
#' @param rcol Transformed right column reference.
#' @return A SQL condition string.
#' @noRd
sql_sublevel_condition <- function(
  sub,
  col,
  dialect,
  null_guard,
  lcol = sql_col_ref('l', col),
  rcol = sql_col_ref('r', col)
) {
  method <- sub$method

  if (method == 'exact') {
    return(glue::glue('{null_guard} AND {lcol} = {rcol}'))
  }
  if (method == 'jaro_winkler') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND jaro_winkler_similarity({lcol}, {rcol}) >= {t}'
    ))
  }
  if (method == 'jaro') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND jaro_similarity({lcol}, {rcol}) >= {t}'
    ))
  }
  if (method == 'jaccard') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND jaccard({lcol}, {rcol}) >= {t}'))
  }
  if (method == 'cosine') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND cosine_similarity({lcol}, {rcol}) >= {t}'
    ))
  }
  if (method == 'levenshtein') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND levenshtein({lcol}, {rcol}) <= {t}'))
  }
  if (method == 'damerau_levenshtein') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND damerau_levenshtein({lcol}, {rcol}) <= {t}'
    ))
  }
  if (method == 'numeric_diff') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) <= {t}'
    ))
  }
  if (method == 'pct_diff') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) / ',
      'NULLIF(GREATEST(ABS(CAST({lcol} AS DOUBLE)), ABS(CAST({rcol} AS DOUBLE))), 0) < {t}'
    ))
  }
  if (method == 'date_diff') {
    t <- sub$thresholds[1]
    mult <- switch(sub$units[1], 'days' = 1, 'months' = 30, 'years' = 365, 1)
    days_val <- t * mult
    diff_expr <- sql_date_diff_expr(lcol, rcol, dialect)
    return(glue::glue('{null_guard} AND {diff_expr} <= {days_val}'))
  }
  if (method == 'time_diff') {
    t <- sub$thresholds[1]
    secs_val <- time_diff_to_seconds(t, sub$units[1])
    diff_expr <- sql_time_diff_expr(lcol, rcol, dialect)
    return(glue::glue('{null_guard} AND {diff_expr} <= {secs_val}'))
  }
  if (method == 'soundex') {
    soundex_fn <- if (identical(dialect, 'duckdb')) 'il_soundex' else 'soundex'
    return(glue::glue(
      '{null_guard} AND {soundex_fn}({lcol}) = {soundex_fn}({rcol})'
    ))
  }
  if (method == 'array_subset') {
    return(glue::glue(
      '{null_guard} AND ARRAY_LENGTH(ARRAY_INTERSECT({lcol}, {rcol})) = ',
      'LEAST(ARRAY_LENGTH({lcol}), ARRAY_LENGTH({rcol}))'
    ))
  }
  if (method == 'array_intersect') {
    t <- sub$thresholds[1]
    return(glue::glue(
      '{null_guard} AND ARRAY_LENGTH(ARRAY_INTERSECT({lcol}, {rcol})) >= {t}'
    ))
  }
  if (method == 'array_min_distance') {
    t <- sub$thresholds[1]
    inner <- sql_array_min_distance_inner(sub$fn, col)
    op <- if (sub$fn == 'jaro_winkler') '>=' else '<='
    return(glue::glue('{null_guard} AND ({inner}) {op} {t}'))
  }
  if (method == 'custom') {
    sql_expr <- glue::glue(
      sub$sql_expr,
      col = sql_quote_identifier(col),
      .open = '{',
      .close = '}'
    )
    return(glue::glue('{null_guard} AND ({sql_expr})'))
  }
  if (method == 'and') {
    parts <- vapply(
      sub$children,
      sql_sublevel_condition,
      character(1),
      col = col,
      dialect = dialect,
      null_guard = null_guard,
      lcol = lcol,
      rcol = rcol
    )
    return(glue::glue('({paste(parts, collapse = ") AND (")})'))
  }
  if (method == 'or') {
    parts <- vapply(
      sub$children,
      sql_sublevel_condition,
      character(1),
      col = col,
      dialect = dialect,
      null_guard = null_guard,
      lcol = lcol,
      rcol = rcol
    )
    return(glue::glue('({paste(parts, collapse = ") OR (")})'))
  }
  if (method == 'not') {
    part <- sql_sublevel_condition(
      sub$child,
      col,
      dialect,
      null_guard,
      lcol,
      rcol
    )
    return(glue::glue('{null_guard} AND NOT ({part})'))
  }
  # Default: exact match
  glue::glue('{null_guard} AND {lcol} = {rcol}')
}

# Build the inner scalar expression that yields the best pairwise score
# for array_min_distance: MAX similarity (jaro_winkler) or MIN distance
# (levenshtein) across all element pairs via UNNEST cross-join.
# Returns a SQL fragment suitable for embedding in a scalar subquery.
sql_array_min_distance_inner <- function(fn, col) {
  agg <- if (fn == 'jaro_winkler') 'MAX' else 'MIN'
  dist_fn <- if (fn == 'jaro_winkler') {
    'jaro_winkler_similarity(lv, rv)'
  } else {
    'levenshtein(lv, rv)'
  }
  qcol <- sql_quote_identifier(col)
  paste0(
    '(SELECT ',
    agg,
    '(',
    dist_fn,
    ') ',
    'FROM UNNEST(l.',
    qcol,
    ') AS t1(lv), UNNEST(r.',
    qcol,
    ') AS t2(rv))'
  )
}

# Build the full multi-threshold CASE expression for array_min_distance.
# Wraps sql_array_min_distance_inner in an outer CASE that maps the best
# score to an integer gamma level (0 = else, K = strictest match).
sql_array_min_distance_case <- function(level, col, null_guard) {
  fn <- level$fn
  thresholds <- level$thresholds
  n <- length(thresholds)
  op <- if (fn == 'jaro_winkler') '>=' else '<='
  inner <- sql_array_min_distance_inner(fn, col)

  when_clauses <- vapply(
    seq_along(thresholds),
    function(i) {
      paste0('WHEN m ', op, ' ', thresholds[i], ' THEN ', n - i + 1L)
    },
    character(1)
  )

  inner_case <- paste0(
    'SELECT CASE ',
    paste(when_clauses, collapse = ' '),
    ' ELSE 0 END ',
    'FROM (SELECT ',
    if (fn == 'jaro_winkler') 'MAX' else 'MIN',
    '(',
    if (fn == 'jaro_winkler') {
      'jaro_winkler_similarity(lv, rv)'
    } else {
      'levenshtein(lv, rv)'
    },
    ') AS m FROM UNNEST(l.',
    sql_quote_identifier(col),
    ') AS t1(lv), UNNEST(r.',
    sql_quote_identifier(col),
    ') AS t2(rv)) sub_m'
  )

  glue::glue(
    'CASE WHEN {null_guard} THEN COALESCE(({inner_case}), 0) ELSE 0 END'
  )
}

#' Build a SQL query that returns pairs with gamma columns computed in SQL
#'
#' Combines blocking rules via UNION, deduplicates, and computes binary
#' gamma values for each comparison using SQL functions.
#'
#' @param model An il_model object.
#' @param blocking_rules List of blocking rule objects.
#' @param limit Optional integer limit on pairs.
#' @return A SQL query string.
#' @noRd
build_gamma_query <- function(
  model,
  blocking_rules,
  limit = NULL,
  deduplicate = FALSE,
  blocked_pairs_tbl = NULL
) {
  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- if (!is.null(model$data$tbl_r)) model$data$tbl_r else tbl_l
  comparisons <- model$spec$comparisons
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

  # Gamma SELECT expressions
  gamma_exprs <- vapply(
    comparisons,
    function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue(
        '{expr} AS {sql_quote_identifier(paste0("gamma_", comparison_name(comp)))}'
      )
    },
    character(1)
  )
  gamma_select <- paste(gamma_exprs, collapse = ', ')

  # TF SELECT expressions (scalar subqueries against pre-computed TF tables)
  tf_cols <- tf_columns(comparisons)
  tf_select <- sql_tf_select_exprs(tf_cols, model$data$tf_tables)
  if (!is.null(tf_select)) {
    gamma_select <- paste(gamma_select, tf_select, sep = ', ')
  }

  if (!is.null(blocked_pairs_tbl)) {
    sql <- build_gamma_query_from_blocked_pairs(
      model,
      blocked_pairs_tbl = blocked_pairs_tbl,
      gamma_select = gamma_select
    )
    if (!is.null(limit)) {
      sql <- glue::glue('{sql} LIMIT {as.integer(limit)}')
    }
    return(sql)
  }

  select_prefix <- glue::glue(
    'SELECT l.unique_id AS l_unique_id, r.unique_id AS r_unique_id, ',
    '{gamma_select} '
  )

  # Build per-table-pair queries: which (left_tbl, right_tbl, condition) combos?
  table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)

  all_parts <- character(0)
  for (tp in table_pairs) {
    if (length(blocking_rules) > 0L) {
      prior_conds <- character(0)
      parts <- vapply(
        seq_along(blocking_rules),
        function(i) {
          br <- blocking_rules[[i]]
          cond <- build_blocking_condition(
            br$columns,
            br$where,
            transform = br$transform,
            dialect = dialect
          )
          from_l <- sql_explode_from(tp$from_l, br$explode, dialect)
          from_r <- sql_explode_from(tp$from_r, br$explode, dialect)
          # Exclude pairs already matched by earlier blocking rules
          if (length(prior_conds) > 0L) {
            exclude <- paste(
              'COALESCE(',
              prior_conds,
              ', FALSE)',
              collapse = ' OR '
            )
            full_cond <- paste0(
              tp$join_cond,
              ' AND ',
              cond,
              ' AND NOT (',
              exclude,
              ')'
            )
          } else {
            full_cond <- paste0(tp$join_cond, ' AND ', cond)
          }
          prior_conds <<- c(prior_conds, cond)
          glue::glue(
            '{select_prefix}',
            'FROM {from_l} l, {from_r} r ',
            'WHERE {full_cond}'
          )
        },
        character(1)
      )
      all_parts <- c(all_parts, parts)
    } else {
      all_parts <- c(
        all_parts,
        glue::glue(
          '{select_prefix}',
          'FROM {sql_quote_identifier(tp$from_l)} l, {sql_quote_identifier(tp$from_r)} r ',
          'WHERE {tp$join_cond}'
        )
      )
    }
  }

  inner <- paste(all_parts, collapse = ' UNION ALL ')

  # Optionally wrap in DISTINCT to deduplicate across blocking rules.
  # With preceding-rule exclusion, duplicates are largely eliminated at
  # source. For EM callers, GROUP BY handles aggregation. For predict
  # callers, dedup is applied after scoring + threshold filtering.

  # GROUP BY handles aggregation.  For predict callers, dedup is applied
  # after scoring + threshold filtering where far fewer rows remain.
  if (deduplicate) {
    sql <- glue::glue('SELECT DISTINCT * FROM ({inner}) AS pairs')
  } else {
    sql <- glue::glue('SELECT * FROM ({inner}) AS pairs')
  }

  if (!is.null(limit)) {
    sql <- glue::glue('{sql} LIMIT {as.integer(limit)}')
  }

  sql
}

#' Build gamma SQL from a materialized blocked-pairs table
#' @noRd
build_gamma_query_from_blocked_pairs <- function(
  model,
  blocked_pairs_tbl,
  gamma_select
) {
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l
  combos <- if (has_two_tables) {
    list(
      list(source_l = 'l', source_r = 'r', from_l = tbl_l, from_r = tbl_r),
      list(source_l = 'l', source_r = 'l', from_l = tbl_l, from_r = tbl_l),
      list(source_l = 'r', source_r = 'r', from_l = tbl_r, from_r = tbl_r)
    )
  } else {
    list(list(source_l = 'l', source_r = 'l', from_l = tbl_l, from_r = tbl_l))
  }

  parts <- vapply(
    combos,
    function(combo) {
      glue::glue(
        'SELECT b.l_unique_id, b.r_unique_id, {gamma_select} ',
        'FROM {sql_quote_identifier(blocked_pairs_tbl)} b ',
        'INNER JOIN {sql_quote_identifier(combo$from_l)} l ON l.unique_id = b.l_unique_id ',
        'INNER JOIN {sql_quote_identifier(combo$from_r)} r ON r.unique_id = b.r_unique_id ',
        "WHERE b.source_l = '{combo$source_l}' ",
        "AND b.source_r = '{combo$source_r}'"
      )
    },
    character(1)
  )

  glue::glue(
    'SELECT DISTINCT * FROM ({paste(parts, collapse = " UNION ALL ")}) AS pairs'
  )
}

#' Build the list of (from_l, from_r, join_cond) table-pair combos
#'
#' For dedupe: one combo (tbl × tbl with id inequality).
#' For link: one combo (tbl_l × tbl_r, no dedup guard needed).
#' For link_and_dedupe: three combos (cross + within-left + within-right).
#'
#' Wrap a table reference with UNNEST for exploding array columns
#'
#' When `explode_cols` is NULL or empty, returns the table name unchanged.
#' Otherwise returns a subquery that unnests the specified array columns.
#'
#' @param tbl Table name.
#' @param explode_cols Character vector of array column names, or NULL.
#' @param dialect SQL dialect string.
#' @return A SQL FROM fragment (either a table name or a parenthesised subquery).
#' @noRd
sql_explode_from <- function(tbl, explode_cols, dialect) {
  qtbl <- sql_quote_identifier(tbl)
  if (is.null(explode_cols) || length(explode_cols) == 0L) {
    return(qtbl)
  }
  if (dialect == 'duckdb') {
    qexplode <- sql_quote_identifier(explode_cols)
    exclude_clause <- paste(qexplode, collapse = ', ')
    unnest_exprs <- paste0(
      'UNNEST(',
      qexplode,
      ') AS ',
      qexplode,
      collapse = ', '
    )
    return(glue::glue(
      '(SELECT * EXCLUDE ({exclude_clause}), {unnest_exprs} FROM {qtbl})'
    ))
  }
  if (dialect == 'postgres') {
    # PostgreSQL: CROSS JOIN LATERAL UNNEST for each array column
    laterals <- vapply(
      seq_along(explode_cols),
      function(i) {
        qcol <- sql_quote_identifier(explode_cols[[i]])
        glue::glue(
          'CROSS JOIN LATERAL UNNEST({qcol}) AS _unnest_{i}({qcol})'
        )
      },
      character(1)
    )
    return(glue::glue(
      '(SELECT * FROM {qtbl} {paste(laterals, collapse = " ")})'
    ))
  }
  cli::cli_warn(
    '{.arg .explode} is not supported for SQLite; ignoring array explosion.'
  )
  qtbl
}

#' Build the set of (left_table, right_table, join_condition) combos
#'
#' @param tbl_l Left table name.
#' @param tbl_r Right table name.
#' @param link_type One of "dedupe", "link", or "link_and_dedupe".
#' @param has_two_tables Logical. TRUE when tbl_l and tbl_r differ.
#' @return A list of lists, each with `from_l`, `from_r`, `join_cond`.
#' @noRd
build_table_pairs <- function(tbl_l, tbl_r, link_type, has_two_tables) {
  if (!has_two_tables || link_type == 'dedupe') {
    # Single table dedupe
    return(list(list(
      from_l = tbl_l,
      from_r = tbl_l,
      join_cond = 'l.unique_id < r.unique_id'
    )))
  }

  if (link_type == 'link') {
    # Cross-table only, no dedup guard needed (different tables)
    return(list(list(
      from_l = tbl_l,
      from_r = tbl_r,
      join_cond = '1=1'
    )))
  }

  # link_and_dedupe: cross-table + within each table
  list(
    list(from_l = tbl_l, from_r = tbl_r, join_cond = '1=1'),
    list(
      from_l = tbl_l,
      from_r = tbl_l,
      join_cond = 'l.unique_id < r.unique_id'
    ),
    list(
      from_l = tbl_r,
      from_r = tbl_r,
      join_cond = 'l.unique_id < r.unique_id'
    )
  )
}

#' Generate SQL for a comparison level
#' @param level An il_comparison_level object.
#' @param col Column name.
#' @param dialect SQL dialect (currently "duckdb" or "sqlite").
#' @return A character SQL fragment.
#' @noRd
sql_for_comparison_level <- function(level, col, dialect = 'duckdb') {
  method <- level$method
  lcol <- sql_col_ref('l', col)
  rcol <- sql_col_ref('r', col)

  if (method == 'exact') {
    return(glue::glue('{lcol} = {rcol}'))
  }

  if (method == 'jaro_winkler') {
    thresholds <- level$thresholds
    fn_name <- if (dialect == 'sqlite') {
      'jaro_winkler_similarity'
    } else {
      'jaro_winkler_similarity'
    }
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN {fn_name}({lcol}, {rcol}) >= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'jaro') {
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN jaro_similarity({lcol}, {rcol}) >= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method %in% c('levenshtein', 'damerau_levenshtein')) {
    thresholds <- level$thresholds
    fn_name <- method
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN {fn_name}({lcol}, {rcol}) <= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'jaccard') {
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN jaccard({lcol}, {rcol}) >= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'cosine') {
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN cosine_similarity({lcol}, {rcol}) >= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'numeric_diff') {
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN ABS({lcol} - {rcol}) <= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'pct_diff') {
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue(
          'WHEN ABS({lcol} - {rcol}) / ',
          'NULLIF(GREATEST(ABS({lcol}), ABS({rcol})), 0) <= {t} THEN {t}'
        )
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'date_diff') {
    thresholds <- level$thresholds
    units <- level$units
    parts <- character(length(thresholds))
    for (i in seq_along(thresholds)) {
      days_val <- switch(
        units[i],
        'days' = thresholds[i],
        'months' = thresholds[i] * 30,
        'years' = thresholds[i] * 365,
        thresholds[i]
      )
      parts[i] <- glue::glue(
        'WHEN {sql_date_diff_expr(lcol, rcol, dialect)} <= {days_val} THEN {i}'
      )
    }
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'time_diff') {
    thresholds <- level$thresholds
    units <- level$units
    parts <- character(length(thresholds))
    for (i in seq_along(thresholds)) {
      secs_val <- time_diff_to_seconds(thresholds[i], units[i])
      parts[i] <- glue::glue(
        'WHEN {sql_time_diff_expr(lcol, rcol, dialect)} <= {secs_val} THEN {i}'
      )
    }
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'geo_distance') {
    if (length(col) != 2L) {
      cli::cli_abort(
        '{.fn cl_geo_distance} comparisons require latitude and longitude columns.'
      )
    }
    lat_l <- sql_col_ref('l', col[1])
    lon_l <- sql_col_ref('l', col[2])
    lat_r <- sql_col_ref('r', col[1])
    lon_r <- sql_col_ref('r', col[2])
    dist <- glue::glue(
      '2 * 6371 * ASIN(SQRT(POWER(SIN(RADIANS(({lat_r} - {lat_l}) / 2)), 2) + ',
      'COS(RADIANS({lat_l})) * COS(RADIANS({lat_r})) * ',
      'POWER(SIN(RADIANS(({lon_r} - {lon_l}) / 2)), 2)))'
    )
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN {dist} <= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'array_intersect') {
    thresholds <- level$thresholds
    parts <- vapply(
      thresholds,
      function(t) {
        glue::glue('WHEN array_intersect_count({lcol}, {rcol}) >= {t} THEN {t}')
      },
      character(1)
    )
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'array_subset') {
    return(glue::glue(
      'CASE WHEN ARRAY_LENGTH(ARRAY_INTERSECT({lcol}, {rcol})) = ',
      'LEAST(ARRAY_LENGTH({lcol}), ARRAY_LENGTH({rcol})) THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'custom') {
    return(glue::glue(
      level$sql_expr,
      col = sql_quote_identifier(col),
      .open = '{',
      .close = '}'
    ))
  }

  if (method == 'null') {
    return(glue::glue('{lcol} IS NULL OR {rcol} IS NULL'))
  }

  if (method == 'levels') {
    parts <- vapply(
      level$levels,
      function(l) {
        sql_for_comparison_level(l, col, dialect = dialect)
      },
      character(1)
    )
    return(paste(parts, collapse = '\n'))
  }

  glue::glue('{lcol} = {rcol}')
}

#' Build aliased SELECT clauses for left/right tables
#'
#' Generates `l.col AS l_col, ...` and `r.col AS r_col, ...`.
#'
#' @param cols Character vector of column names.
#' @return A named list with `left` and `right` SQL fragments.
#' @noRd
build_select_aliases <- function(cols) {
  list(
    left = paste(
      vapply(
        cols,
        function(col) {
          glue::glue(
            '{sql_col_ref("l", col)} AS {sql_quote_identifier(paste0("l_", col))}'
          )
        },
        character(1)
      ),
      collapse = ', '
    ),
    right = paste(
      vapply(
        cols,
        function(col) {
          glue::glue(
            '{sql_col_ref("r", col)} AS {sql_quote_identifier(paste0("r_", col))}'
          )
        },
        character(1)
      ),
      collapse = ', '
    )
  )
}

#' Build a WHERE clause for blocking on equality
#'
#' @param columns Character vector of column names to block on.
#' @param where Optional raw SQL string for non-equality conditions.
#' @param transform Optional transform function applied to both sides.
#' @param dialect Optional SQL dialect string for phonetic transforms.
#' @return A character string like `"l.col1 = r.col1 AND l.col2 = r.col2"`.
#' @noRd
build_blocking_condition <- function(
  columns,
  where = NULL,
  transform = NULL,
  dialect = NULL
) {
  parts <- character(0)
  if (length(columns) > 0L) {
    parts <- vapply(
      columns,
      function(col) {
        col_tf <- if (is.list(transform)) transform[[col]] else transform
        lcol <- sql_transform_col(sql_col_ref('l', col), col_tf, dialect)
        rcol <- sql_transform_col(sql_col_ref('r', col), col_tf, dialect)
        glue::glue('{lcol} = {rcol}')
      },
      character(1)
    )
  }
  if (!is.null(where) && !is.na(where) && nzchar(where)) {
    parts <- c(parts, where)
  }
  paste(parts, collapse = ' AND ')
}

#' Build and execute a pair-count query
#'
#' Counts pairs produced by a blocking rule, handling dedupe vs link.
#'
#' @param con A DBI connection.
#' @param tbl_l Left table name.
#' @param tbl_r Right table name (same as tbl_l for dedupe).
#' @param where A SQL WHERE fragment for blocking.
#' @param dedupe Logical. If TRUE, add `l.unique_id < r.unique_id`.
#' @return Integer count of pairs.
#' @noRd
count_blocked_pairs <- function(con, tbl_l, tbl_r, where, dedupe = TRUE) {
  qtbl_l <- sql_quote_identifier(tbl_l)
  qtbl_r <- sql_quote_identifier(tbl_r)
  if (dedupe) {
    sql <- glue::glue(
      'SELECT COUNT(*) AS n FROM {qtbl_l} l, {qtbl_r} r ',
      'WHERE l.unique_id < r.unique_id AND {where}'
    )
  } else {
    sql <- glue::glue(
      'SELECT COUNT(*) AS n FROM {qtbl_l} l, {qtbl_r} r WHERE {where}'
    )
  }
  res <- DBI::dbGetQuery(con, sql)
  as.numeric(res$n[1])
}

#' Build SQL for unique blocked-pair rows across blocking rules
#'
#' @param tbl_l Left table name.
#' @param tbl_r Right table name.
#' @param rule An il_blocking_rule object.
#' @param link_type One of "dedupe", "link", or "link_and_dedupe".
#' @param has_two_tables Logical. TRUE when tbl_l and tbl_r differ.
#' @param dialect SQL dialect string.
#' @return SQL selecting source/id columns for blocked pairs.
#' @noRd
blocked_pair_rows_sql <- function(
  tbl_l,
  tbl_r,
  rule,
  link_type,
  has_two_tables,
  dialect
) {
  block_where <- build_blocking_condition(
    rule$columns,
    rule$where,
    transform = rule$transform,
    dialect = dialect
  )
  table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
  parts <- vapply(
    seq_along(table_pairs),
    function(i) {
      tp <- table_pairs[[i]]
      source_l <- if (identical(tp$from_l, tbl_l)) 'l' else 'r'
      source_r <- if (identical(tp$from_r, tbl_l)) 'l' else 'r'
      from_l <- sql_explode_from(tp$from_l, rule$explode, dialect)
      from_r <- sql_explode_from(tp$from_r, rule$explode, dialect)
      where_parts <- c(tp$join_cond)
      if (nzchar(block_where)) {
        where_parts <- c(where_parts, block_where)
      }
      where_clause <- paste(where_parts, collapse = ' AND ')
      glue::glue(
        "SELECT '{source_l}' AS source_l, l.unique_id AS unique_id_l, ",
        "'{source_r}' AS source_r, r.unique_id AS unique_id_r ",
        'FROM {from_l} l, {from_r} r ',
        'WHERE {where_clause}'
      )
    },
    character(1)
  )
  paste(parts, collapse = ' UNION ALL ')
}

#' Count unique blocked pairs across all deterministic rules
#'
#' Unlike summing per-rule counts, this counts a pair only once even when it is
#' produced by multiple blocking rules.
#'
#' @param con A DBI connection.
#' @param tbl_l Left table name.
#' @param tbl_r Right table name.
#' @param rules List of il_blocking_rule objects.
#' @param link_type One of "dedupe", "link", or "link_and_dedupe".
#' @param dialect SQL dialect string.
#' @return Numeric count of unique blocked pairs.
#' @noRd
count_unique_blocked_pairs <- function(
  con,
  tbl_l,
  tbl_r,
  rules,
  link_type,
  dialect,
  profile = NULL
) {
  has_two_tables <- !is.null(tbl_r) && !identical(tbl_r, tbl_l)
  tbl_r <- tbl_r %||% tbl_l
  parts <- vapply(
    rules,
    function(rule) {
      blocked_pair_rows_sql(
        tbl_l,
        tbl_r,
        rule,
        link_type,
        has_two_tables,
        dialect
      )
    },
    character(1)
  )
  union_sql <- paste(parts, collapse = ' UNION ALL ')
  sql <- glue::glue(
    'SELECT COUNT(*) AS n FROM (',
    'SELECT DISTINCT source_l, unique_id_l, source_r, unique_id_r ',
    'FROM ({union_sql}) AS blocked_pairs',
    ') AS unique_blocked_pairs'
  )
  res <- il_db_get_query(
    con,
    sql,
    step = 'estimate_prior.count_unique_blocked_pairs',
    profile = profile
  )
  as.numeric(res$n[1])
}

# --- SQL-side scoring helpers (lazy prediction pipeline) --------------------

#' Generate a CASE expression for one comparison's match-weight contribution
#'
#' Pre-computes log2(m/u) per gamma level in R and embeds the constants
#' as SQL CASE branches.
#'
#' @param comp_name Column name of the comparison.
#' @param m_vec Numeric vector of m probabilities (one per gamma level).
#' @param u_vec Numeric vector of u probabilities (one per gamma level).
#' @return A SQL expression string.
#' @noRd
sql_weight_case <- function(comp_name, m_vec, u_vec) {
  weights <- log2(pmax(m_vec, 1e-10) / pmax(u_vec, 1e-10))
  whens <- vapply(
    seq_along(weights),
    function(i) {
      glue::glue('WHEN {i - 1L} THEN {weights[i]}')
    },
    character(1)
  )
  gamma_col <- sql_quote_identifier(paste0('gamma_', comp_name))
  glue::glue(
    'CAST(CASE {gamma_col} {paste(whens, collapse = " ")} ELSE 0.0 END AS DOUBLE)'
  )
}

#' Generate a CASE expression for TF adjustment of one comparison
#'
#' Returns a weighted log2 adjustment when gamma equals the highest level,
#' 0 otherwise. Supports `tf_adjustment_weight` (power scaling, default 1)
#' and `tf_minimum_u_value` (floor on TF denominator, default 0).
#' Uses LN(x)/LN(2) for portability across DuckDB and PostgreSQL.
#'
#' @param col Column name.
#' @param max_level Integer: highest gamma level (exact match).
#' @param u_exact Numeric: u probability at the highest gamma level.
#' @param tf_adjustment_weight Numeric power scaling (default 1.0).
#' @param tf_minimum_u_value Numeric floor for TF denominator (default 0.0).
#' @return A SQL expression string.
#' @noRd
sql_tf_adj_expr <- function(
  col,
  max_level,
  u_exact,
  tf_adjustment_weight = 1.0,
  tf_minimum_u_value = 0.0
) {
  if (tf_adjustment_weight == 0) {
    return('CAST(0.0 AS DOUBLE)')
  }
  log2_u <- log2(max(u_exact, 1e-10))
  ln2 <- log(2)
  gamma_col <- sql_quote_identifier(paste0('gamma_', col))
  tf_col_l <- sql_quote_identifier(paste0('tf_', col, '_l'))
  tf_col_r <- sql_quote_identifier(paste0('tf_', col, '_r'))
  # Build TF divisor using COALESCE so that when only one side has a TF
  # value the available value is used (matches splink's coalesce approach
  # and the R-side pmax(na.rm=TRUE) path).
  tf_coalesce_lr <- glue::glue(
    'COALESCE({tf_col_l}, {tf_col_r})'
  )
  tf_coalesce_rl <- glue::glue(
    'COALESCE({tf_col_r}, {tf_col_l})'
  )
  tf_max_expr <- glue::glue(
    'GREATEST({tf_coalesce_lr}, {tf_coalesce_rl})'
  )
  if (tf_minimum_u_value > 0) {
    tf_divisor <- glue::glue(
      'GREATEST({tf_max_expr}, {tf_minimum_u_value})'
    )
  } else {
    tf_divisor <- tf_max_expr
  }
  adj_expr <- glue::glue('{log2_u} - LN({tf_divisor}) / {ln2}')
  if (tf_adjustment_weight != 1.0) {
    adj_expr <- glue::glue('{tf_adjustment_weight} * ({adj_expr})')
  }
  glue::glue(
    'CAST(CASE WHEN {gamma_col} = {max_level} ',
    'AND {tf_coalesce_lr} IS NOT NULL ',
    'AND {tf_divisor} > 0 ',
    'THEN {adj_expr} ',
    'ELSE 0.0 END AS DOUBLE)'
  )
}

#' Build a complete SQL query that scores and filters pairs
#'
#' Wraps `build_gamma_query()` with per-comparison weight CASE expressions,
#' TF adjustments, and a match-probability logistic transform.  The result
#' is a query whose output columns match [predict.il_model()].
#'
#' @param model A trained il_model object.
#' @param threshold Numeric match-probability threshold.
#' @return A SQL query string.
#' @noRd
build_scored_query <- function(
  model,
  threshold = 0.85,
  threshold_match_weight = NULL,
  blocked_pairs_tbl = NULL
) {
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- clamp_probability(safe_prior(model))
  comp_names <- comparison_names(comparisons)
  blocking_rules <- model$spec$blocking_rules

  mu <- extract_mu_vectors(params, comp_names)
  gamma_sql <- build_gamma_query(
    model,
    blocking_rules,
    blocked_pairs_tbl = blocked_pairs_tbl
  )

  # Per-comparison weight CASE expressions
  weight_parts <- vapply(
    seq_along(comparisons),
    function(j) {
      cn <- comp_names[j]
      sql_weight_case(cn, mu$m_levels[[cn]], mu$u_levels[[cn]])
    },
    character(1)
  )

  # TF adjustment CASE expressions (both for sum and as separate columns)
  tf_parts <- character(0)
  tf_adj_selects <- character(0)
  for (j in seq_along(comparisons)) {
    comp <- comparisons[[j]]
    if (isTRUE(comp$method$term_frequency)) {
      col <- comp$columns
      max_level <- n_gamma_levels(comp$method) - 1L
      u_exact <- mu$u_levels[[col]][max_level + 1L]
      tf_w <- comp$tf_adjustment_weight %||% 1.0
      tf_min <- comp$tf_minimum_u_value %||% 0.0
      expr <- sql_tf_adj_expr(col, max_level, u_exact, tf_w, tf_min)
      tf_parts <- c(tf_parts, expr)
      tf_adj_selects <- c(
        tf_adj_selects,
        glue::glue(
          '({expr}) AS {sql_quote_identifier(paste0("tf_adj_", col))}'
        )
      )
    }
  }

  all_weight_parts <- c(weight_parts, tf_parts)
  weight_expr <- paste(all_weight_parts, collapse = ' + ')

  log_prior_odds <- log(prior / (1 - prior))
  prior_weight <- prior_match_weight(prior)
  ln2 <- log(2)

  gamma_cols <- paste0('gamma_', comp_names)
  gamma_select <- sql_identifier_csv(gamma_cols)

  # tf_adj columns: inner SELECT computes them, outer just references by name
  inner_tf_adj <- ''
  outer_tf_adj <- ''
  if (length(tf_adj_selects) > 0L) {
    inner_tf_adj <- paste0(', ', paste(tf_adj_selects, collapse = ', '))
    tf_col_names <- vapply(
      comparisons[vapply(
        comparisons,
        function(c) {
          isTRUE(c$method$term_frequency)
        },
        logical(1)
      )],
      function(c) c$columns,
      character(1)
    )
    outer_tf_adj <- paste0(
      ', ',
      sql_identifier_csv(paste0('tf_adj_', tf_col_names))
    )
  }

  # Choose filter: match_weight threshold or match_probability threshold
  if (!is.null(threshold_match_weight)) {
    where_clause <- glue::glue('WHERE match_weight >= {threshold_match_weight}')
  } else {
    where_clause <- glue::glue(
      'WHERE 1.0 / (1.0 + EXP(-({log_prior_odds} + match_weight * {ln2}))) >= {threshold}'
    )
  }

  # Two-level nesting:
  #   Inner: gamma query + match_weight + tf_adj columns
  #   Outer: match_probability + threshold filter + DISTINCT (dedup here,
  #          not in build_gamma_query, so we deduplicate fewer rows)
  glue::glue(
    'SELECT DISTINCT unique_id_l, unique_id_r, {gamma_select}, ',
    'match_weight{outer_tf_adj}, ',
    '(match_weight + {prior_weight}) AS total_match_weight, ',
    '1.0 / (1.0 + EXP(-({log_prior_odds} + match_weight * {ln2}))) ',
    'AS match_probability ',
    'FROM (',
    'SELECT l_unique_id AS unique_id_l, r_unique_id AS unique_id_r, ',
    '{gamma_select}{inner_tf_adj}, ',
    '({weight_expr}) AS match_weight ',
    'FROM ({gamma_sql}) AS gamma_pairs',
    ') AS weighted_pairs ',
    '{where_clause}'
  )
}

#' Wrap scored pairs with deterministic greedy one-to-one matching
#'
#' Applies the same greedy resolver used by the collected path, but keeps
#' all candidate scoring and assignment inside the database.  DuckDB and
#' PostgreSQL use different list/array syntax in the recursive state.
#'
#' @param model A trained `il_model`.
#' @param inner_sql Character scalar: the scored-pairs SQL query to wrap.
#' @return A SQL query string with greedy one-to-one pairs.
#' @noRd
build_greedy_query <- function(model, inner_sql) {
  con <- model$con
  dialect <- detect_dialect(con)

  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l
  qtbl_l <- DBI::dbQuoteIdentifier(con, tbl_l)
  qtbl_r <- DBI::dbQuoteIdentifier(con, tbl_r)

  result_cols <- greedy_result_columns(model)
  result_select <- paste(
    paste0('p.', DBI::dbQuoteIdentifier(con, result_cols)),
    collapse = ', '
  )

  if (identical(dialect, 'duckdb')) {
    used_l_init <- 'list_value(unique_id_l)'
    used_r_init <- 'list_value(unique_id_r)'
    used_l_next <- 'list_append(g.used_l, p.unique_id_l)'
    used_r_next <- 'list_append(g.used_r, p.unique_id_r)'
    unused_l <- 'NOT list_contains(g.used_l, p2.unique_id_l)'
    unused_r <- 'NOT list_contains(g.used_r, p2.unique_id_r)'
  } else if (identical(dialect, 'postgres')) {
    used_l_init <- 'ARRAY[unique_id_l]'
    used_r_init <- 'ARRAY[unique_id_r]'
    used_l_next <- 'array_append(g.used_l, p.unique_id_l)'
    used_r_next <- 'array_append(g.used_r, p.unique_id_r)'
    unused_l <- 'NOT p2.unique_id_l = ANY(g.used_l)'
    unused_r <- 'NOT p2.unique_id_r = ANY(g.used_r)'
  } else {
    cli::cli_abort(
      '{.arg greedy = TRUE} with {.arg collect = FALSE} requires a DuckDB or PostgreSQL backend.'
    )
  }

  glue::glue(
    'WITH RECURSIVE ',
    'scored_pairs AS ({inner_sql}), ',
    'left_rows AS (',
    'SELECT unique_id, ROW_NUMBER() OVER () AS row_index_l FROM {qtbl_l}',
    '), ',
    'right_rows AS (',
    'SELECT unique_id, ROW_NUMBER() OVER () AS row_index_r FROM {qtbl_r}',
    '), ',
    'ranked_pairs AS (',
    'SELECT s.*, ',
    'ROW_NUMBER() OVER (',
    'ORDER BY s.match_probability DESC, l.row_index_l, r.row_index_r',
    ') AS greedy_rank ',
    'FROM scored_pairs AS s ',
    'LEFT JOIN left_rows AS l ON s.unique_id_l = l.unique_id ',
    'LEFT JOIN right_rows AS r ON s.unique_id_r = r.unique_id',
    '), ',
    'greedy(greedy_rank, unique_id_l, unique_id_r, used_l, used_r) AS (',
    'SELECT greedy_rank, unique_id_l, unique_id_r, ',
    '{used_l_init} AS used_l, {used_r_init} AS used_r ',
    'FROM ranked_pairs ',
    'WHERE greedy_rank = (SELECT MIN(greedy_rank) FROM ranked_pairs) ',
    'UNION ALL ',
    'SELECT p.greedy_rank, p.unique_id_l, p.unique_id_r, ',
    '{used_l_next} AS used_l, {used_r_next} AS used_r ',
    'FROM greedy AS g ',
    'JOIN ranked_pairs AS p ON p.greedy_rank = (',
    'SELECT MIN(p2.greedy_rank) FROM ranked_pairs AS p2 ',
    'WHERE p2.greedy_rank > g.greedy_rank ',
    'AND {unused_l} AND {unused_r}',
    ')',
    ') ',
    'SELECT {result_select} ',
    'FROM ranked_pairs AS p ',
    'INNER JOIN greedy AS g ON p.greedy_rank = g.greedy_rank ',
    'ORDER BY p.greedy_rank'
  )
}

#' Output columns emitted by a scored-pairs query
#' @param model A trained `il_model`.
#' @return Character vector of output column names.
#' @noRd
greedy_result_columns <- function(model) {
  comp_names <- comparison_names(model$spec$comparisons)
  tf_cols <- vapply(
    model$spec$comparisons,
    function(c) {
      if (isTRUE(c$method$term_frequency)) c$columns else NA_character_
    },
    character(1)
  )
  tf_cols <- tf_cols[!is.na(tf_cols)]

  c(
    'unique_id_l',
    'unique_id_r',
    paste0('gamma_', comp_names),
    'match_weight',
    if (length(tf_cols) > 0L) paste0('tf_adj_', tf_cols) else character(0),
    'total_match_weight',
    'match_probability'
  )
}

#' Wrap a scored-pairs query with LEFT JOINs to the source tables
#'
#' Produces a SQL query that augments the scored-pairs output with the
#' original field values from the left and right source tables, using
#' `_l` / `_r` suffixes.  Used by `predict_lazy()` when
#' `include_fields = TRUE`.
#'
#' @param model A trained `il_model`.
#' @param inner_sql Character scalar: the scored-pairs SQL query to wrap.
#' @return A SQL query string with field columns appended.
#' @noRd
build_fields_join_query <- function(model, inner_sql) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  all_cols_l <- DBI::dbListFields(con, tbl_l)
  field_cols_l <- setdiff(all_cols_l, 'unique_id')

  if (length(field_cols_l) == 0L) {
    return(inner_sql)
  }

  field_cols_r <- if (tbl_r == tbl_l) {
    field_cols_l
  } else {
    setdiff(DBI::dbListFields(con, tbl_r), 'unique_id')
  }

  l_cols <- paste(
    vapply(
      field_cols_l,
      function(col) {
        qcol <- DBI::dbQuoteIdentifier(con, col)
        qalias <- DBI::dbQuoteIdentifier(con, paste0(col, '_l'))
        glue::glue('l.{qcol} AS {qalias}')
      },
      character(1)
    ),
    collapse = ', '
  )

  r_cols <- paste(
    vapply(
      field_cols_r,
      function(col) {
        qcol <- DBI::dbQuoteIdentifier(con, col)
        qalias <- DBI::dbQuoteIdentifier(con, paste0(col, '_r'))
        glue::glue('r.{qcol} AS {qalias}')
      },
      character(1)
    ),
    collapse = ', '
  )

  qtbl_l <- DBI::dbQuoteIdentifier(con, tbl_l)
  qtbl_r <- DBI::dbQuoteIdentifier(con, tbl_r)

  glue::glue(
    'SELECT s.*, {l_cols}, {r_cols} ',
    'FROM ({inner_sql}) AS s ',
    'LEFT JOIN {qtbl_l} AS l ON s.unique_id_l = l.unique_id ',
    'LEFT JOIN {qtbl_r} AS r ON s.unique_id_r = r.unique_id'
  )
}
