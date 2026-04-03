# Internal SQL generation functions for comparison levels, blocking rules,
# and join conditions. Not exported.

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
  # Phonetic transforms need special handling (dialect-dependent, some
  # have multi-arg SQL signatures)
  phonetic_sql <- phonetic_transform_sql(transform, col_ref, dialect)
  if (!is.null(phonetic_sql)) {
    return(phonetic_sql)
  }
  fn_name <- transform_to_sql_fn(transform)
  if (is.null(fn_name)) {
    return(col_ref)
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

#' Can this transform be translated to SQL?
#' @noRd
transform_has_sql <- function(transform) {
  !is.null(transform_to_sql_fn(transform)) || is_phonetic_transform(transform)
}

#' Map an R function to a serializable name
#' @noRd
transform_to_name <- function(transform) {
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
  cli::cli_warn('Custom transform cannot be serialized; it will be lost on save/load.')
  NULL
}

#' Map a serialized name back to an R function
#' @noRd
name_to_transform <- function(name) {
  if (is.null(name)) {
    return(NULL)
  }
  switch(name,
    'tolower' = tolower,
    'toupper' = toupper,
    'trimws' = trimws,
    'il_soundex' = il_soundex,
    'il_metaphone' = il_metaphone,
    'il_dmetaphone' = il_dmetaphone,
    NULL
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
  supported <- switch(fn_name,
    'il_soundex'    = c('duckdb', 'postgres'),
    'il_metaphone'  = 'postgres',
    'il_dmetaphone' = 'postgres',
    character(0)
  )
  if (!dialect %in% supported) {
    label <- switch(fn_name,
      'il_soundex'    = 'Soundex',
      'il_metaphone'  = 'Metaphone',
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

  # Build column references with optional transforms
  lcol <- sql_transform_col(glue::glue('l.{col}'), tf, dialect)
  rcol <- sql_transform_col(glue::glue('r.{col}'), tf, dialect)

  null_guard <- glue::glue(
    'l.{col} IS NOT NULL AND r.{col} IS NOT NULL'
  )

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
    whens <- vapply(seq_along(thresholds), function(i) {
      glue::glue('WHEN {null_guard} AND jaro_winkler_similarity({lcol}, {rcol}) >= {thresholds[i]} THEN {n - i + 1L}')
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'jaro') {
    n <- length(thresholds)
    whens <- vapply(seq_along(thresholds), function(i) {
      glue::glue('WHEN {null_guard} AND jaro_similarity({lcol}, {rcol}) >= {thresholds[i]} THEN {n - i + 1L}')
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'levenshtein') {
    n <- length(thresholds)
    whens <- vapply(seq_along(thresholds), function(i) {
      glue::glue('WHEN {null_guard} AND levenshtein({lcol}, {rcol}) <= {thresholds[i]} THEN {n - i + 1L}')
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'damerau_levenshtein') {
    n <- length(thresholds)
    whens <- vapply(seq_along(thresholds), function(i) {
      glue::glue('WHEN {null_guard} AND damerau_levenshtein({lcol}, {rcol}) <= {thresholds[i]} THEN {n - i + 1L}')
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'numeric_diff') {
    n <- length(thresholds)
    whens <- vapply(seq_along(thresholds), function(i) {
      glue::glue('WHEN {null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) <= {thresholds[i]} THEN {n - i + 1L}')
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'pct_diff') {
    n <- length(thresholds)
    whens <- vapply(seq_along(thresholds), function(i) {
      glue::glue(
        'WHEN {null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) / ',
        'NULLIF(GREATEST(ABS(CAST({lcol} AS DOUBLE)), ABS(CAST({rcol} AS DOUBLE))), 0) <= {thresholds[i]} THEN {n - i + 1L}'
      )
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'date_diff') {
    n <- length(thresholds)
    whens <- vapply(seq_along(thresholds), function(i) {
      mult <- switch(level$units[i],
        'days' = 1,
        'months' = 30,
        'years' = 365,
        1
      )
      days_val <- thresholds[i] * mult
      if (dialect == 'duckdb') {
        glue::glue('WHEN {null_guard} AND ABS(CAST({lcol} AS DATE) - CAST({rcol} AS DATE)) <= {days_val} THEN {n - i + 1L}')
      } else {
        glue::glue('WHEN {null_guard} AND ABS(JULIANDAY({lcol}) - JULIANDAY({rcol})) <= {days_val} THEN {n - i + 1L}')
      }
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
  }

  if (method == 'levels') {
    # Build multi-level CASE from sublevels (skip null and else)
    sublevels <- Filter(function(l) {
      !isTRUE(l$is_null_level) && !isTRUE(l$is_else_level)
    }, level$levels)
    n <- length(sublevels)
    if (n == 0L) {
      return(glue::glue(
        'CASE WHEN {null_guard} AND {lcol} = {rcol} THEN 1 ELSE 0 END'
      ))
    }
    whens <- vapply(seq_along(sublevels), function(i) {
      sub <- sublevels[[i]]
      cond <- sql_sublevel_condition(sub, col, dialect, null_guard, lcol, rcol)
      glue::glue('WHEN {cond} THEN {n - i + 1L}')
    }, character(1))
    return(glue::glue('CASE {paste(whens, collapse = " ")} ELSE 0 END'))
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
sql_sublevel_condition <- function(sub, col, dialect, null_guard,
                                   lcol = paste0('l.', col),
                                   rcol = paste0('r.', col)) {
  method <- sub$method

  if (method == 'exact') {
    return(glue::glue('{null_guard} AND {lcol} = {rcol}'))
  }
  if (method == 'jaro_winkler') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND jaro_winkler_similarity({lcol}, {rcol}) >= {t}'))
  }
  if (method == 'jaro') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND jaro_similarity({lcol}, {rcol}) >= {t}'))
  }
  if (method == 'levenshtein') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND levenshtein({lcol}, {rcol}) <= {t}'))
  }
  if (method == 'damerau_levenshtein') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND damerau_levenshtein({lcol}, {rcol}) <= {t}'))
  }
  if (method == 'numeric_diff') {
    t <- sub$thresholds[1]
    return(glue::glue('{null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) <= {t}'))
  }
  if (method == 'date_diff') {
    t <- sub$thresholds[1]
    mult <- switch(sub$units[1],
      'days' = 1,
      'months' = 30,
      'years' = 365,
      1
    )
    days_val <- t * mult
    if (dialect == 'duckdb') {
      return(glue::glue('{null_guard} AND ABS(CAST({lcol} AS DATE) - CAST({rcol} AS DATE)) <= {days_val}'))
    }
    return(glue::glue('{null_guard} AND ABS(JULIANDAY({lcol}) - JULIANDAY({rcol})) <= {days_val}'))
  }
  if (method == 'custom') {
    sql_expr <- glue::glue(sub$sql_expr, col = col, .open = '{', .close = '}')
    return(glue::glue('{null_guard} AND ({sql_expr})'))
  }
  # Default: exact match
  glue::glue('{null_guard} AND {lcol} = {rcol}')
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
build_gamma_query <- function(model, blocking_rules, limit = NULL) {
  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- if (!is.null(model$data$tbl_r)) model$data$tbl_r else tbl_l
  comparisons <- model$spec$comparisons
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

  # Gamma SELECT expressions
  gamma_exprs <- vapply(comparisons, function(comp) {
    expr <- sql_gamma_case(comp, dialect)
    glue::glue('{expr} AS gamma_{comp$columns}')
  }, character(1))
  gamma_select <- paste(gamma_exprs, collapse = ', ')

  # TF SELECT expressions (scalar subqueries against pre-computed TF tables)
  tf_cols <- tf_columns(comparisons)
  tf_select <- sql_tf_select_exprs(tf_cols)
  if (!is.null(tf_select)) {
    gamma_select <- paste(gamma_select, tf_select, sep = ', ')
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
      parts <- vapply(blocking_rules, function(br) {
        cond <- build_blocking_condition(br$columns, br$where,
          transform = br$transform,
          dialect = dialect
        )
        glue::glue(
          '{select_prefix}',
          'FROM {tp$from_l} l, {tp$from_r} r ',
          'WHERE {tp$join_cond} AND {cond}'
        )
      }, character(1))
      all_parts <- c(all_parts, parts)
    } else {
      all_parts <- c(all_parts, glue::glue(
        '{select_prefix}',
        'FROM {tp$from_l} l, {tp$from_r} r ',
        'WHERE {tp$join_cond}'
      ))
    }
  }

  inner <- paste(all_parts, collapse = ' UNION ')

  # Wrap in DISTINCT to deduplicate across blocking rules and table combos
  sql <- glue::glue(
    'SELECT DISTINCT * FROM ({inner}) AS pairs'
  )

  if (!is.null(limit)) {
    sql <- glue::glue('{sql} LIMIT {as.integer(limit)}')
  }

  sql
}

#' Build the list of (from_l, from_r, join_cond) table-pair combos
#'
#' For dedupe: one combo (tbl × tbl with id inequality).
#' For link: one combo (tbl_l × tbl_r, no dedup guard needed).
#' For link_and_dedupe: three combos (cross + within-left + within-right).
#'
#' @param tbl_l Left table name.
#' @param tbl_r Right table name.
#' @param link_type One of "dedupe", "link", or "link_and_dedupe".
#' @param has_two_tables Logical; TRUE when tbl_l and tbl_r differ.
#' @return A list of lists, each with `from_l`, `from_r`, `join_cond`.
#' @noRd
build_table_pairs <- function(tbl_l, tbl_r, link_type, has_two_tables) {
  if (!has_two_tables || link_type == 'dedupe') {
    # Single table dedupe
    return(list(list(
      from_l = tbl_l, from_r = tbl_l,
      join_cond = 'l.unique_id < r.unique_id'
    )))
  }

  if (link_type == 'link') {
    # Cross-table only, no dedup guard needed (different tables)
    return(list(list(
      from_l = tbl_l, from_r = tbl_r,
      join_cond = '1=1'
    )))
  }

  # link_and_dedupe: cross-table + within each table
  list(
    list(from_l = tbl_l, from_r = tbl_r, join_cond = '1=1'),
    list(
      from_l = tbl_l, from_r = tbl_l,
      join_cond = 'l.unique_id < r.unique_id'
    ),
    list(
      from_l = tbl_r, from_r = tbl_r,
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

  if (method == 'exact') {
    return(glue::glue('l.{col} = r.{col}'))
  }

  if (method == 'jaro_winkler') {
    thresholds <- level$thresholds
    fn_name <- if (dialect == 'sqlite') 'jaro_winkler_similarity' else 'jaro_winkler_similarity'
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN {fn_name}(l.{col}, r.{col}) >= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'jaro') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN jaro_similarity(l.{col}, r.{col}) >= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method %in% c('levenshtein', 'damerau_levenshtein')) {
    thresholds <- level$thresholds
    fn_name <- method
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN {fn_name}(l.{col}, r.{col}) <= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'jaccard') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN jaccard(l.{col}, r.{col}) >= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'cosine') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN cosine_similarity(l.{col}, r.{col}) >= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'numeric_diff') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN ABS(l.{col} - r.{col}) <= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'pct_diff') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue(
        'WHEN ABS(l.{col} - r.{col}) / ',
        'NULLIF(GREATEST(ABS(l.{col}), ABS(r.{col})), 0) <= {t} THEN {t}'
      )
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'date_diff') {
    thresholds <- level$thresholds
    units <- level$units
    parts <- character(length(thresholds))
    for (i in seq_along(thresholds)) {
      days_val <- switch(units[i],
        'days' = thresholds[i],
        'months' = thresholds[i] * 30,
        'years' = thresholds[i] * 365,
        thresholds[i]
      )
      parts[i] <- glue::glue(
        'WHEN ABS(JULIANDAY(l.{col}) - JULIANDAY(r.{col})) <= {days_val} THEN {i}'
      )
    }
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'distance_km') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN distance_km(l.{col}, r.{col}) <= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'array_intersect') {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue('WHEN array_intersect_count(l.{col}, r.{col}) >= {t} THEN {t}')
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == 'custom') {
    return(level$sql_expr)
  }

  if (method == 'null') {
    return(glue::glue('l.{col} IS NULL OR r.{col} IS NULL'))
  }

  if (method == 'levels') {
    parts <- vapply(level$levels, function(l) {
      sql_for_comparison_level(l, col, dialect = dialect)
    }, character(1))
    return(paste(parts, collapse = '\n'))
  }

  glue::glue('l.{col} = r.{col}')
}

#' Generate SQL for a single blocking rule
#' @param rule An il_blocking_rule object.
#' @param dialect SQL dialect.
#' @return A character SQL fragment.
#' @noRd
sql_for_blocking_rule <- function(rule, dialect = 'duckdb') {
  columns <- rule$columns
  conditions <- vapply(columns, function(col) {
    glue::glue('l.{col} = r.{col}')
  }, character(1))
  paste(conditions, collapse = ' AND ')
}

#' Generate SQL for multiple blocking rules (OR-ed)
#' @param rules A list of il_blocking_rule objects.
#' @param dialect SQL dialect.
#' @return A character SQL fragment.
#' @noRd
sql_for_blocking_rules <- function(rules, dialect = 'duckdb') {
  parts <- vapply(rules, function(r) {
    paste0('(', sql_for_blocking_rule(r, dialect = dialect), ')')
  }, character(1))
  paste(parts, collapse = ' OR ')
}

#' Generate the join condition for dedupe vs link
#' @param link_type "dedupe" or "link".
#' @return A character SQL fragment.
#' @noRd
sql_join_condition <- function(link_type = 'dedupe') {
  if (link_type == 'dedupe') {
    return('l.unique_id < r.unique_id')
  }
  'l.__source_table <> r.__source_table'
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
    left = paste(glue::glue('l.{cols} AS l_{cols}'), collapse = ', '),
    right = paste(glue::glue('r.{cols} AS r_{cols}'), collapse = ', ')
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
build_blocking_condition <- function(columns, where = NULL, transform = NULL,
                                     dialect = NULL) {
  parts <- character(0)
  if (length(columns) > 0L) {
    parts <- vapply(columns, function(col) {
      lcol <- sql_transform_col(glue::glue('l.{col}'), transform, dialect)
      rcol <- sql_transform_col(glue::glue('r.{col}'), transform, dialect)
      glue::glue('{lcol} = {rcol}')
    }, character(1))
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
#' @param dedupe Logical; if TRUE, add `l.unique_id < r.unique_id`.
#' @return Integer count of pairs.
#' @noRd
count_blocked_pairs <- function(con, tbl_l, tbl_r, where, dedupe = TRUE) {
  if (dedupe) {
    sql <- glue::glue(
      'SELECT COUNT(*) AS n FROM {tbl_l} l, {tbl_r} r ',
      'WHERE l.unique_id < r.unique_id AND {where}'
    )
  } else {
    sql <- glue::glue(
      'SELECT COUNT(*) AS n FROM {tbl_l} l, {tbl_r} r WHERE {where}'
    )
  }
  res <- DBI::dbGetQuery(con, sql)
  as.integer(res$n[1])
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
  whens <- vapply(seq_along(weights), function(i) {
    glue::glue('WHEN {i - 1L} THEN {weights[i]}')
  }, character(1))
  glue::glue(
    'CASE gamma_{comp_name} {paste(whens, collapse = " ")} ELSE 0.0 END'
  )
}

#' Generate a CASE expression for TF adjustment of one comparison
#'
#' Returns log2(u_exact / max(tf_l, tf_r)) when gamma equals the highest
#' level, 0 otherwise.  Uses LN(x)/LN(2) for portability across DuckDB
#' and PostgreSQL.
#'
#' @param col Column name.
#' @param max_level Integer: highest gamma level (exact match).
#' @param u_exact Numeric: u probability at the highest gamma level.
#' @return A SQL expression string.
#' @noRd
sql_tf_adj_expr <- function(col, max_level, u_exact) {
  log2_u <- log2(max(u_exact, 1e-10))
  ln2 <- log(2)
  glue::glue(
    'CASE WHEN gamma_{col} = {max_level} ',
    'AND tf_{col}_l IS NOT NULL AND tf_{col}_r IS NOT NULL ',
    'AND GREATEST(tf_{col}_l, tf_{col}_r) > 0 ',
    'THEN {log2_u} - LN(GREATEST(tf_{col}_l, tf_{col}_r)) / {ln2} ',
    'ELSE 0.0 END'
  )
}

#' Build a complete SQL query that scores and filters pairs
#'
#' Wraps [build_gamma_query()] with per-comparison weight CASE expressions,
#' TF adjustments, and a match-probability logistic transform.  The result
#' is a query whose output columns match [predict.il_model()].
#'
#' @param model A trained il_model object.
#' @param threshold Numeric match-probability threshold.
#' @return A SQL query string.
#' @noRd
build_scored_query <- function(model, threshold = 0.85) {
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- model$params$prior %||% 0.05
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  blocking_rules <- model$spec$blocking_rules

  mu <- extract_mu_vectors(params, comp_names)
  gamma_sql <- build_gamma_query(model, blocking_rules)

  # Per-comparison weight CASE expressions
  weight_parts <- vapply(seq_along(comparisons), function(j) {
    cn <- comp_names[j]
    sql_weight_case(cn, mu$m_levels[[cn]], mu$u_levels[[cn]])
  }, character(1))

  # TF adjustment CASE expressions (both for sum and as separate columns)
  tf_parts <- character(0)
  tf_adj_selects <- character(0)
  for (j in seq_along(comparisons)) {
    comp <- comparisons[[j]]
    if (isTRUE(comp$method$term_frequency)) {
      col <- comp$columns
      max_level <- n_gamma_levels(comp$method) - 1L
      u_exact <- mu$u_levels[[col]][max_level + 1L]
      expr <- sql_tf_adj_expr(col, max_level, u_exact)
      tf_parts <- c(tf_parts, expr)
      tf_adj_selects <- c(
        tf_adj_selects,
        glue::glue('({expr}) AS tf_adj_{col}')
      )
    }
  }

  all_weight_parts <- c(weight_parts, tf_parts)
  weight_expr <- paste(all_weight_parts, collapse = ' + ')

  log_prior_odds <- log(prior / (1 - prior))
  ln2 <- log(2)

  gamma_cols <- paste0('gamma_', comp_names)
  gamma_select <- paste(gamma_cols, collapse = ', ')

  # tf_adj columns: inner SELECT computes them, outer just references by name
  inner_tf_adj <- ''
  outer_tf_adj <- ''
  if (length(tf_adj_selects) > 0L) {
    inner_tf_adj <- paste0(', ', paste(tf_adj_selects, collapse = ', '))
    tf_col_names <- vapply(comparisons[vapply(comparisons, function(c) {
      isTRUE(c$method$term_frequency)
    }, logical(1))], function(c) c$columns, character(1))
    outer_tf_adj <- paste0(', ', paste0('tf_adj_', tf_col_names, collapse = ', '))
  }

  # Two-level nesting:
  #   Inner: gamma query + match_weight + tf_adj columns
  #   Outer: match_probability + threshold filter
  glue::glue(
    'SELECT unique_id_l, unique_id_r, {gamma_select}, ',
    'match_weight{outer_tf_adj}, ',
    '1.0 / (1.0 + EXP(-({log_prior_odds} + match_weight * {ln2}))) ',
    'AS match_probability ',
    'FROM (',
    'SELECT l_unique_id AS unique_id_l, r_unique_id AS unique_id_r, ',
    '{gamma_select}{inner_tf_adj}, ',
    '({weight_expr}) AS match_weight ',
    'FROM ({gamma_sql}) AS gamma_pairs',
    ') AS weighted_pairs ',
    'WHERE 1.0 / (1.0 + EXP(-({log_prior_odds} + match_weight * {ln2}))) >= {threshold}'
  )
}

#' Wrap a scored-pairs query with LEFT JOINs to the source tables
#'
#' Produces a SQL query that augments the scored-pairs output with the
#' original field values from the left and right source tables, using
#' `_l` / `_r` suffixes.  Used by [predict_lazy()] when
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

  l_cols <- paste(vapply(field_cols_l, function(col) {
    qcol <- DBI::dbQuoteIdentifier(con, col)
    qalias <- DBI::dbQuoteIdentifier(con, paste0(col, '_l'))
    glue::glue('l.{qcol} AS {qalias}')
  }, character(1)), collapse = ', ')

  r_cols <- paste(vapply(field_cols_r, function(col) {
    qcol <- DBI::dbQuoteIdentifier(con, col)
    qalias <- DBI::dbQuoteIdentifier(con, paste0(col, '_r'))
    glue::glue('r.{qcol} AS {qalias}')
  }, character(1)), collapse = ', ')

  qtbl_l <- DBI::dbQuoteIdentifier(con, tbl_l)
  qtbl_r <- DBI::dbQuoteIdentifier(con, tbl_r)

  glue::glue(
    'SELECT s.*, {l_cols}, {r_cols} ',
    'FROM ({inner_sql}) AS s ',
    'LEFT JOIN {qtbl_l} AS l ON s.unique_id_l = l.unique_id ',
    'LEFT JOIN {qtbl_r} AS r ON s.unique_id_r = r.unique_id'
  )
}
