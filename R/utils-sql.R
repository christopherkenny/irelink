# Internal SQL generation functions for comparison levels, blocking rules,
# and join conditions. Not exported.

#' Generate SQL for a comparison level
#' @param level An il_comparison_level object.
#' @param col Column name.
#' @param dialect SQL dialect (currently "duckdb" or "sqlite").
#' @return A character SQL fragment.
#' @noRd
sql_for_comparison_level <- function(level, col, dialect = "duckdb") {
  method <- level$method

  if (method == "exact") {
    return(glue::glue("l.{col} = r.{col}"))
  }

  if (method == "jaro_winkler") {
    thresholds <- level$thresholds
    fn_name <- if (dialect == "sqlite") "jaro_winkler_similarity" else "jaro_winkler_similarity"
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN {fn_name}(l.{col}, r.{col}) >= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "jaro") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN jaro_similarity(l.{col}, r.{col}) >= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method %in% c("levenshtein", "damerau_levenshtein")) {
    thresholds <- level$thresholds
    fn_name <- method
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN {fn_name}(l.{col}, r.{col}) <= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "jaccard") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN jaccard(l.{col}, r.{col}) >= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "cosine") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN cosine_similarity(l.{col}, r.{col}) >= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "numeric_diff") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN ABS(l.{col} - r.{col}) <= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "pct_diff") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue(
        "WHEN ABS(l.{col} - r.{col}) / ",
        "NULLIF(GREATEST(ABS(l.{col}), ABS(r.{col})), 0) <= {t} THEN {t}"
      )
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "date_diff") {
    thresholds <- level$thresholds
    units <- level$units
    parts <- character(length(thresholds))
    for (i in seq_along(thresholds)) {
      days_val <- switch(units[i],
        "days" = thresholds[i],
        "months" = thresholds[i] * 30,
        "years" = thresholds[i] * 365,
        thresholds[i]
      )
      parts[i] <- glue::glue(
        "WHEN ABS(JULIANDAY(l.{col}) - JULIANDAY(r.{col})) <= {days_val} THEN {i}"
      )
    }
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "distance_km") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN distance_km(l.{col}, r.{col}) <= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "array_intersect") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      glue::glue("WHEN array_intersect_count(l.{col}, r.{col}) >= {t} THEN {t}")
    }, character(1))
    return(glue::glue("CASE {paste(parts, collapse = ' ')} ELSE -1 END"))
  }

  if (method == "custom") {
    return(level$sql_expr)
  }

  if (method == "null") {
    return(glue::glue("l.{col} IS NULL OR r.{col} IS NULL"))
  }

  if (method == "levels") {
    parts <- vapply(level$levels, function(l) {
      sql_for_comparison_level(l, col, dialect = dialect)
    }, character(1))
    return(paste(parts, collapse = "\n"))
  }

  glue::glue("l.{col} = r.{col}")
}

#' Generate SQL for a single blocking rule
#' @param rule An il_blocking_rule object.
#' @param dialect SQL dialect.
#' @return A character SQL fragment.
#' @noRd
sql_for_blocking_rule <- function(rule, dialect = "duckdb") {
  columns <- rule$columns
  conditions <- vapply(columns, function(col) {
    glue::glue("l.{col} = r.{col}")
  }, character(1))
  paste(conditions, collapse = " AND ")
}

#' Generate SQL for multiple blocking rules (OR-ed)
#' @param rules A list of il_blocking_rule objects.
#' @param dialect SQL dialect.
#' @return A character SQL fragment.
#' @noRd
sql_for_blocking_rules <- function(rules, dialect = "duckdb") {
  parts <- vapply(rules, function(r) {
    paste0("(", sql_for_blocking_rule(r, dialect = dialect), ")")
  }, character(1))
  paste(parts, collapse = " OR ")
}

#' Generate the join condition for dedupe vs link
#' @param link_type "dedupe" or "link".
#' @return A character SQL fragment.
#' @noRd
sql_join_condition <- function(link_type = "dedupe") {
  if (link_type == "dedupe") {
    return("l.unique_id < r.unique_id")
  }
  "l.__source_table <> r.__source_table"
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
    left = paste(glue::glue("l.{cols} AS l_{cols}"), collapse = ", "),
    right = paste(glue::glue("r.{cols} AS r_{cols}"), collapse = ", ")
  )
}

#' Build a WHERE clause for blocking on equality
#'
#' @param columns Character vector of column names to block on.
#' @return A character string like `"l.col1 = r.col1 AND l.col2 = r.col2"`.
#' @noRd
build_blocking_condition <- function(columns) {
  conds <- vapply(columns, function(col) {
    glue::glue("l.{col} = r.{col}")
  }, character(1))
  paste(conds, collapse = " AND ")
}

#' Build and execute a pair-count query
#'
#' Counts pairs produced by a blocking rule, handling dedupe vs link.
#'
#' @param con A DBI connection.
#' @param tbl_l Left table name.
#' @param tbl_r Right table name (same as tbl_l for dedupe).
#' @param where A SQL WHERE fragment for blocking.
#' @param dedupe Logical; if TRUE, add `l.rowid < r.rowid`.
#' @return Integer count of pairs.
#' @noRd
count_blocked_pairs <- function(con, tbl_l, tbl_r, where, dedupe = TRUE) {
  if (dedupe) {
    sql <- glue::glue(
      "SELECT COUNT(*) AS n FROM {tbl_l} l, {tbl_r} r ",
      "WHERE l.rowid < r.rowid AND {where}"
    )
  } else {
    sql <- glue::glue(
      "SELECT COUNT(*) AS n FROM {tbl_l} l, {tbl_r} r WHERE {where}"
    )
  }
  res <- DBI::dbGetQuery(con, sql)
  as.integer(res$n[1])
}
