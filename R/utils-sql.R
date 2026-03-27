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

#' Generate a binary gamma CASE expression (0/1) for one comparison
#'
#' Used to push gamma computation into SQL for backends that support
#' string similarity functions (DuckDB, PostgreSQL).
#'
#' @param comp A comparison entry from the spec (with $columns, $method).
#' @param dialect SQL dialect string.
#' @return A SQL expression that evaluates to 0 or 1.
#' @noRd
sql_gamma_case <- function(comp, dialect) {
  col <- comp$columns
  level <- comp$method
  method <- level$method
  thresholds <- level$thresholds

  null_guard <- glue::glue(
    'l.{col} IS NOT NULL AND r.{col} IS NOT NULL'
  )

  if (method == 'exact') {
    return(glue::glue(
      'CASE WHEN {null_guard} AND l.{col} = r.{col} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'jaro_winkler') {
    t <- thresholds[1]
    return(glue::glue(
      'CASE WHEN {null_guard} AND jaro_winkler_similarity(l.{col}, r.{col}) >= {t} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'jaro') {
    t <- thresholds[1]
    return(glue::glue(
      'CASE WHEN {null_guard} AND jaro_similarity(l.{col}, r.{col}) >= {t} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'levenshtein') {
    t <- thresholds[1]
    return(glue::glue(
      'CASE WHEN {null_guard} AND levenshtein(l.{col}, r.{col}) <= {t} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'damerau_levenshtein') {
    t <- thresholds[1]
    return(glue::glue(
      'CASE WHEN {null_guard} AND damerau_levenshtein(l.{col}, r.{col}) <= {t} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'numeric_diff') {
    t <- thresholds[1]
    return(glue::glue(
      'CASE WHEN {null_guard} AND ABS(CAST(l.{col} AS DOUBLE) - CAST(r.{col} AS DOUBLE)) <= {t} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'pct_diff') {
    t <- thresholds[1]
    return(glue::glue(
      'CASE WHEN {null_guard} AND ABS(CAST(l.{col} AS DOUBLE) - CAST(r.{col} AS DOUBLE)) / ',
      'NULLIF(GREATEST(ABS(CAST(l.{col} AS DOUBLE)), ABS(CAST(r.{col} AS DOUBLE))), 0) <= {t} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'date_diff') {
    t <- thresholds[1]
    unit <- level$units[1]
    mult <- switch(unit,
      'days' = 1,
      'months' = 30,
      'years' = 365,
      1
    )
    days_val <- t * mult
    if (dialect == 'duckdb') {
      return(glue::glue(
        'CASE WHEN {null_guard} AND ABS(CAST(l.{col} AS DATE) - CAST(r.{col} AS DATE)) <= {days_val} THEN 1 ELSE 0 END'
      ))
    }
    return(glue::glue(
      'CASE WHEN {null_guard} AND ABS(JULIANDAY(l.{col}) - JULIANDAY(r.{col})) <= {days_val} THEN 1 ELSE 0 END'
    ))
  }

  if (method == 'levels') {
    for (sublevel in level$levels) {
      if (!isTRUE(sublevel$is_null_level) && !isTRUE(sublevel$is_else_level)) {
        inner_comp <- list(columns = col, method = sublevel)
        return(sql_gamma_case(inner_comp, dialect))
      }
    }
  }

  # Fallback: exact match
  glue::glue(
    'CASE WHEN {null_guard} AND l.{col} = r.{col} THEN 1 ELSE 0 END'
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
        cond <- build_blocking_condition(br$columns, br$where)
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
    list(from_l = tbl_l, from_r = tbl_l,
         join_cond = 'l.unique_id < r.unique_id'),
    list(from_l = tbl_r, from_r = tbl_r,
         join_cond = 'l.unique_id < r.unique_id')
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
#' @return A character string like `"l.col1 = r.col1 AND l.col2 = r.col2"`.
#' @noRd
build_blocking_condition <- function(columns, where = NULL) {
  parts <- character(0)
  if (length(columns) > 0L) {
    parts <- vapply(columns, function(col) {
      glue::glue('l.{col} = r.{col}')
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
