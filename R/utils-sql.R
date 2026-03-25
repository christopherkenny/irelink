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
    return(sprintf("l.%s = r.%s", col, col))
  }

  if (method == "jaro_winkler") {
    thresholds <- level$thresholds
    fn_name <- if (dialect == "sqlite") "jaro_winkler_similarity" else "jaro_winkler_similarity"
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN %s(l.%s, r.%s) >= %s THEN %s", fn_name, col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "jaro") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN jaro_similarity(l.%s, r.%s) >= %s THEN %s", col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method %in% c("levenshtein", "damerau_levenshtein")) {
    thresholds <- level$thresholds
    fn_name <- method
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN %s(l.%s, r.%s) <= %s THEN %s", fn_name, col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "jaccard") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN jaccard(l.%s, r.%s) >= %s THEN %s", col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "cosine") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN cosine_similarity(l.%s, r.%s) >= %s THEN %s", col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "numeric_diff") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN ABS(l.%s - r.%s) <= %s THEN %s", col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "pct_diff") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf(
        "WHEN ABS(l.%s - r.%s) / NULLIF(GREATEST(ABS(l.%s), ABS(r.%s)), 0) <= %s THEN %s",
        col, col, col, col, t, t
      )
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
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
      parts[i] <- sprintf(
        "WHEN ABS(JULIANDAY(l.%s) - JULIANDAY(r.%s)) <= %s THEN %s",
        col, col, days_val, i
      )
    }
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "distance_km") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN distance_km(l.%s, r.%s) <= %s THEN %s", col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "array_intersect") {
    thresholds <- level$thresholds
    parts <- vapply(thresholds, function(t) {
      sprintf("WHEN array_intersect_count(l.%s, r.%s) >= %s THEN %s", col, col, t, t)
    }, character(1))
    return(sprintf("CASE %s ELSE -1 END", paste(parts, collapse = " ")))
  }

  if (method == "custom") {
    return(level$sql_expr)
  }

  if (method == "null") {
    return(sprintf("l.%s IS NULL OR r.%s IS NULL", col, col))
  }

  if (method == "levels") {
    parts <- vapply(level$levels, function(l) {
      sql_for_comparison_level(l, col, dialect = dialect)
    }, character(1))
    return(paste(parts, collapse = "\n"))
  }

  sprintf("l.%s = r.%s", col, col)
}

#' Generate SQL for a single blocking rule
#' @param rule An il_blocking_rule object.
#' @param dialect SQL dialect.
#' @return A character SQL fragment.
#' @noRd
sql_for_blocking_rule <- function(rule, dialect = "duckdb") {
  columns <- rule$columns
  conditions <- vapply(columns, function(col) {
    sprintf("l.%s = r.%s", col, col)
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
