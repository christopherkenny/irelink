# Internal DBI wrappers with optional lightweight profiling.

#' Create a SQL profile collector
#' @noRd
il_new_sql_profile <- function(enabled = FALSE) {
  if (!isTRUE(enabled)) return(NULL)
  env <- new.env(parent = emptyenv())
  env$entries <- list()
  env
}

#' Append a SQL profile entry
#' @noRd
il_profile_append <- function(profile, step, elapsed, rows = NA_integer_,
                              statement = NULL) {
  if (is.null(profile)) return(invisible(NULL))
  profile$entries[[length(profile$entries) + 1L]] <- list(
    step = step %||% NA_character_,
    elapsed = as.numeric(elapsed),
    rows = as.integer(rows),
    statement = statement %||% NA_character_
  )
  invisible(NULL)
}

#' Return SQL profile entries as a tibble
#' @noRd
il_sql_profile_entries <- function(profile) {
  if (is.null(profile) || length(profile$entries) == 0L) {
    return(tibble::tibble(
      step = character(0),
      elapsed = numeric(0),
      rows = integer(0),
      statement = character(0)
    ))
  }
  tibble::as_tibble(do.call(rbind, lapply(profile$entries, as.data.frame)))
}

#' Execute a SQL statement with optional profiling
#' @noRd
il_db_execute <- function(con, sql, step = NULL, profile = NULL) {
  timing <- system.time({
    result <- DBI::dbExecute(con, sql)
  })
  il_profile_append(profile, step, timing[['elapsed']], rows = result,
    statement = sql
  )
  result
}

#' Query SQL with optional profiling
#' @noRd
il_db_get_query <- function(con, sql, step = NULL, profile = NULL) {
  timing <- system.time({
    result <- DBI::dbGetQuery(con, sql)
  })
  il_profile_append(profile, step, timing[['elapsed']], rows = nrow(result),
    statement = sql
  )
  result
}
