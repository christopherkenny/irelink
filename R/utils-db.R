# Internal DBI wrappers with optional lightweight profiling.

#' Create a SQL profile collector
#' @noRd
il_new_sql_profile <- function(enabled = FALSE) {
  if (!isTRUE(enabled)) {
    return(NULL)
  }
  env <- new.env(parent = emptyenv())
  env$entries <- list()
  env
}

#' Append a SQL profile entry
#' @noRd
il_profile_append <- function(
  profile,
  step,
  elapsed,
  rows = NA_integer_,
  statement = NULL
) {
  if (is.null(profile)) {
    return(invisible(NULL))
  }
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

#' Print a SQL statement when `options(irelink.show_sql = TRUE)`
#' @noRd
il_show_sql <- function(sql, step = NULL) {
  if (isTRUE(getOption('irelink.show_sql', FALSE))) {
    if (!is.null(step)) {
      cli::cli_verbatim(paste0('-- ', step))
    }
    cli::cli_verbatim(format_sql(sql))
  }
  invisible(NULL)
}

#' Lay out SQL for display
#'
#' Starts a new line before each clause, `WHEN`, `ELSE`, and select-list item,
#' and indents by parenthesis and `CASE` depth. Quoted strings and identifiers
#' are left untouched. Only whitespace changes, so this is for printing only.
#' @noRd
format_sql <- function(sql) {
  pattern <- paste0(
    "'(?:[^']|'')*'",
    '|"(?:[^"]|"")*"',
    '|[A-Za-z_][A-Za-z0-9_]*',
    '|\\s+',
    '|.'
  )
  tokens <- regmatches(sql, gregexpr(pattern, sql, perl = TRUE))[[1]]
  words <- toupper(tokens)
  is_space <- grepl('^\\s+$', tokens)
  clauses <- c(
    'SELECT',
    'FROM',
    'WHERE',
    'GROUP',
    'ORDER',
    'HAVING',
    'LIMIT',
    'UNION'
  )
  joins <- c('LEFT', 'RIGHT', 'INNER', 'FULL', 'CROSS')

  neighbour_word <- function(i, step) {
    j <- i + step
    while (j >= 1L && j <= length(tokens) && is_space[j]) {
      j <- j + step
    }
    if (j < 1L || j > length(tokens)) {
      return('')
    }
    words[j]
  }

  out <- tokens
  depth <- 0L
  case_depth <- 0L
  clause_at <- character(0)
  skip_space <- FALSE
  indent <- function(extra = 0L) {
    paste0('\n', strrep('  ', depth + case_depth + extra))
  }

  for (i in seq_along(tokens)) {
    w <- words[i]
    if (is_space[i]) {
      out[i] <- ' '
      if (skip_space) {
        out[i] <- ''
      }
      next
    }
    skip_space <- FALSE

    is_join <- (w %in% joins && neighbour_word(i, 1L) %in% c('JOIN', 'OUTER')) ||
      (w == 'JOIN' && !neighbour_word(i, -1L) %in% c(joins, 'OUTER'))
    is_case_branch <- w %in% c('WHEN', 'ELSE') && case_depth > 0L
    is_condition <- w %in% c('AND', 'OR') &&
      case_depth == 0L &&
      identical(clause_at[depth + 1L], 'WHERE')
    closes_subquery <- FALSE

    if (w == 'END' && case_depth > 0L) {
      case_depth <- case_depth - 1L
    }
    if (tokens[i] == ')') {
      closes_subquery <- !is.na(clause_at[depth + 1L] %||% NA_character_)
      depth <- max(depth - 1L, 0L)
    }
    breaks <- i > 1L &&
      (w %in% clauses || is_join || is_case_branch || closes_subquery)
    if (breaks || is_condition) {
      if (is_space[i - 1L]) {
        out[i - 1L] <- ''
      }
      extra <- 0L
      if (is_case_branch || is_condition) {
        extra <- 1L
      }
      out[i] <- paste0(indent(extra), tokens[i])
    }

    if (w %in% clauses) {
      clause_at[depth + 1L] <- w
    }
    if (w == 'CASE') {
      case_depth <- case_depth + 1L
    }
    if (tokens[i] == '(') {
      depth <- depth + 1L
      clause_at[depth + 1L] <- NA_character_
    }
    if (
      tokens[i] == ',' &&
        case_depth == 0L &&
        identical(clause_at[depth + 1L], 'SELECT')
    ) {
      out[i] <- paste0(',', indent(1L))
      skip_space <- TRUE
    }
  }
  paste(out, collapse = '')
}

#' Execute a SQL statement with optional profiling
#' @noRd
il_db_execute <- function(con, sql, step = NULL, profile = NULL) {
  il_show_sql(sql, step)
  # Skip system.time() when not profiling; it can add a GC pause per statement.
  if (is.null(profile)) {
    return(DBI::dbExecute(con, sql))
  }
  timing <- system.time(result <- DBI::dbExecute(con, sql), gcFirst = FALSE)
  il_profile_append(
    profile,
    step,
    timing[['elapsed']],
    rows = result,
    statement = sql
  )
  result
}

#' Query SQL with optional profiling
#' @noRd
il_db_get_query <- function(con, sql, step = NULL, profile = NULL) {
  il_show_sql(sql, step)
  if (is.null(profile)) {
    return(DBI::dbGetQuery(con, sql))
  }
  timing <- system.time(result <- DBI::dbGetQuery(con, sql), gcFirst = FALSE)
  il_profile_append(
    profile,
    step,
    timing[['elapsed']],
    rows = nrow(result),
    statement = sql
  )
  result
}
