#' Extract a Substring Column Transform
#'
#' Returns a transform that extracts a fixed-width substring from a string
#' column. The result can be passed as the `transform` argument to
#' [il_compare()] or [il_block_on()], and composed with other transforms
#' via [il_transform()]. On DuckDB, the computation is
#' pushed into SQL.
#'
#' @param start Integer start position (1-indexed).
#' @param length Integer number of characters to extract.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' tf <- il_substr(1, 3)
#' tf(c('Johnson', 'Smith', 'Lee'))
#'
#' # Use for blocking on the first 3 characters of a name
#' spec <- il_spec() |>
#'   il_block_on(last_name, .transform = il_substr(1, 3))
il_substr <- function(start, length) {
  if (
    !is.numeric(start) ||
      length(start) != 1L ||
      start < 1L ||
      start != as.integer(start)
  ) {
    cli::cli_abort('{.arg start} must be a positive integer.')
  }
  if (
    !is.numeric(length) ||
      length(length) != 1L ||
      length < 1L ||
      length != as.integer(length)
  ) {
    cli::cli_abort('{.arg length} must be a positive integer.')
  }
  start <- as.integer(start)
  length <- as.integer(length)
  fn <- function(x) substr(x, start, start + length - 1L)
  new_column_transform(
    fn,
    'il_substr',
    list(start = start, length = length)
  )
}

#' Regex Extraction Column Transform
#'
#' Returns a transform that extracts a regex match from a string column.
#' Returns `NA` when no match is found. The result can be passed as the
#' `transform` argument to [il_compare()] or [il_block_on()], and
#' composed with other transforms via [il_transform()]. On DuckDB and
#' DuckDB, the computation is pushed into SQL.
#'
#' @param pattern A regular expression.
#' @param group Integer capture group to extract. Use `0` for the whole
#'   match, or a positive integer for a numbered capture group.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' # Extract a 5-digit ZIP code from a freeform address string
#' tf <- il_regex_extract('\\d{5}')
#' tf(c('Apt 4, 90210', '10001-1234', 'no zip'))
il_regex_extract <- function(pattern, group = 0L) {
  if (!is.character(pattern) || length(pattern) != 1L) {
    cli::cli_abort('{.arg pattern} must be a single character string.')
  }
  if (
    !is.numeric(group) ||
      length(group) != 1L ||
      group < 0L ||
      group != as.integer(group)
  ) {
    cli::cli_abort('{.arg group} must be a non-negative integer.')
  }
  group <- as.integer(group)
  fn <- function(x) {
    x <- as.character(x)
    result <- rep(NA_character_, length(x))
    present <- !is.na(x)
    if (!any(present)) {
      return(result)
    }
    m <- regexpr(pattern, x[present], perl = TRUE)
    matched <- m > 0L
    if (group == 0L) {
      out <- rep(NA_character_, length(m))
      out[matched] <- regmatches(x[present], m)
      result[present] <- out
      return(result)
    }

    starts <- attr(m, 'capture.start')
    lengths <- attr(m, 'capture.length')
    if (is.null(starts) || ncol(starts) < group) {
      return(result)
    }
    out <- rep(NA_character_, length(m))
    group_start <- starts[, group]
    group_length <- lengths[, group]
    has_group <- matched & group_start > 0L & group_length >= 0L
    out[has_group] <- substring(
      x[present][has_group],
      group_start[has_group],
      group_start[has_group] + group_length[has_group] - 1L
    )
    result[present] <- out
    result
  }
  new_column_transform(
    fn,
    'il_regex_extract',
    list(pattern = pattern, group = group)
  )
}

#' Replace a Value with NA Column Transform
#'
#' Returns a transform that replaces a specific value with `NA`. Commonly
#' used to convert empty strings to `NA` before comparison so that
#' missing-data levels are triggered correctly. The result can be passed
#' as the `transform` argument to [il_compare()] or [il_block_on()], and
#' composed with other transforms via [il_transform()]. On DuckDB and
#' DuckDB, maps to SQL `NULLIF`.
#'
#' @param value The value to treat as missing.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' tf <- il_nullif('')
#' tf(c('New York', '', 'Chicago'))
#'
#' # Use before comparison to treat blank city as missing
#' spec <- il_spec() |>
#'   il_compare(city, cl_exact(), transform = il_nullif(''))
il_nullif <- function(value) {
  if (!is.character(value) || length(value) != 1L) {
    cli::cli_abort('{.arg value} must be a single character string.')
  }
  fn <- function(x) ifelse(x == value, NA_character_, x)
  new_column_transform(fn, 'il_nullif', list(value = value))
}

#' Cast to String Column Transform
#'
#' Returns a transform that casts any column to a character/VARCHAR type.
#' Useful when a numeric or date column needs to be compared as text. The
#' result can be passed as the `transform` argument to [il_compare()] or
#' [il_block_on()], and composed with other transforms via [il_transform()].
#' On DuckDB, maps to SQL `CAST(col AS VARCHAR)`.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' tf <- il_cast_to_string()
#' tf(c(12345L, 67890L))
il_cast_to_string <- function() {
  fn <- function(x) as.character(x)
  new_column_transform(fn, 'il_cast_to_string', list())
}

#' Try-Parse Date Column Transform
#'
#' Returns a transform that attempts to parse a string column as a date.
#' Unlike `as.Date()`, failures return `NA`/`NULL` rather than raising an
#' error. On DuckDB this uses `try_strptime()`.
#' The result can be passed as the `transform` argument to [il_compare()]
#' or [il_block_on()], and composed with other transforms via
#' [il_transform()].
#'
#' @param format A `strptime`-style format string. Defaults to `"%Y-%m-%d"`.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' tf <- il_try_parse_date()
#' tf(c('2020-01-15', 'not-a-date', '1985-06-30'))
#'
#' # Non-ISO format
#' tf2 <- il_try_parse_date('%m/%d/%Y')
#' tf2(c('01/15/2020', 'bad'))
il_try_parse_date <- function(format = '%Y-%m-%d') {
  if (!is.character(format) || length(format) != 1L) {
    cli::cli_abort('{.arg format} must be a single character string.')
  }
  fn <- function(x) as.character(as.Date(x, format = format))
  new_column_transform(fn, 'il_try_parse_date', list(format = format))
}

#' Try-Parse Timestamp Column Transform
#'
#' Returns a transform that attempts to parse a string column as a
#' timestamp. Unlike `as.POSIXct()`, failures return `NA`/`NULL` rather
#' than raising an error. On DuckDB this uses `try_strptime()`, and on
#' DuckDB it uses `try_strptime()`. The result can be passed as the
#' `transform` argument to [il_compare()] or [il_block_on()], and
#' composed with other transforms via [il_transform()].
#'
#' @param format A `strptime`-style format string. Defaults to
#'   `"%Y-%m-%d %H:%M:%S"`.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' tf <- il_try_parse_timestamp()
#' tf(c('2020-01-15 08:30:00', 'not-a-timestamp', '1985-06-30 12:00:00'))
#'
#' # Custom format
#' tf2 <- il_try_parse_timestamp('%m/%d/%Y %I:%M %p')
#' tf2(c('01/15/2020 08:30 AM', 'bad'))
il_try_parse_timestamp <- function(format = '%Y-%m-%d %H:%M:%S') {
  if (!is.character(format) || length(format) != 1L) {
    cli::cli_abort('{.arg format} must be a single character string.')
  }
  fn <- function(x) as.character(as.POSIXct(x, format = format, tz = 'UTC'))
  new_column_transform(fn, 'il_try_parse_timestamp', list(format = format))
}

#' Array Element Column Transform
#'
#' Returns a transform that extracts the first or last element of an
#' array-valued column. The result can be passed as the `transform`
#' argument to [il_compare()] or [il_block_on()], and composed with
#' other transforms via [il_transform()]. On DuckDB,
#' maps to SQL array indexing (`col[1]` or `col[-1]`).
#'
#' @param position Either `"first"` or `"last"`.
#'
#' @return An `il_column_transform` closure.
#' @export
#'
#' @examples
#' tf <- il_array_element('first')
#' tf(list(c('Alice', 'A'), c('Bob'), character(0)))
il_array_element <- function(position = c('first', 'last')) {
  position <- match.arg(position)
  fn <- function(x) {
    if (is.list(x)) {
      vapply(
        x,
        function(el) {
          if (length(el) == 0L) {
            NA_character_
          } else if (position == 'first') {
            as.character(el[[1L]])
          } else {
            as.character(el[[length(el)]])
          }
        },
        character(1)
      )
    } else {
      x
    }
  }
  new_column_transform(fn, 'il_array_element', list(position = position))
}

#' Build a column transform closure
#' @noRd
new_column_transform <- function(fn, type, params) {
  attr(fn, 'transform_type') <- type
  attr(fn, 'params') <- params
  class(fn) <- c('il_column_transform', 'function')
  fn
}

#' Check whether an object is a parameterized column transform
#' @noRd
is_column_transform <- function(x) {
  inherits(x, 'il_column_transform')
}

#' Generate SQL for a parameterized column transform
#'
#' @param transform An `il_column_transform` object.
#' @param col_ref Character SQL column reference.
#' @param dialect Optional SQL dialect string.
#' @return A SQL expression string.
#' @noRd
column_transform_sql <- function(transform, col_ref, dialect = NULL) {
  type <- attr(transform, 'transform_type')
  p <- attr(transform, 'params')

  switch(
    type,
    'il_substr' = paste0(
      'SUBSTRING(',
      col_ref,
      ', ',
      p$start,
      ', ',
      p$length,
      ')'
    ),
    'il_regex_extract' = {
      inner <- paste0(
        'regexp_extract(',
        col_ref,
        ', ',
        sql_quote_literal(p$pattern),
        ', ',
        p$group,
        ')'
      )
      paste0('NULLIF(', inner, ', ', sql_quote_literal(''), ')')
    },
    'il_nullif' = paste0(
      'NULLIF(',
      col_ref,
      ', ',
      sql_quote_literal(p$value),
      ')'
    ),
    'il_cast_to_string' = paste0('CAST(', col_ref, ' AS VARCHAR)'),
    'il_try_parse_date' = {
      if (identical(dialect, 'duckdb')) {
        paste0(
          'CAST(try_strptime(',
          col_ref,
          ', ',
          sql_quote_literal(p$format),
          ') AS DATE)'
        )
      } else {
        cli::cli_abort(
          '{.fn il_try_parse_date} SQL translation requires a DuckDB backend.'
        )
      }
    },
    'il_try_parse_timestamp' = {
      if (identical(dialect, 'duckdb')) {
        paste0('try_strptime(', col_ref, ', ', sql_quote_literal(p$format), ')')
      } else {
        cli::cli_abort(
          '{.fn il_try_parse_timestamp} SQL translation requires a DuckDB backend.'
        )
      }
    },
    'il_array_element' = {
      if (!identical(dialect, 'duckdb')) {
        cli::cli_abort(
          '{.fn il_array_element} SQL translation requires a DuckDB backend.'
        )
      }
      if (p$position == 'first') {
        paste0(col_ref, '[1]')
      } else {
        paste0(col_ref, '[-1]')
      }
    },
    col_ref
  )
}

#' Quote a scalar SQL string literal
#' @noRd
sql_quote_literal <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort('SQL literals must be single non-missing strings.')
  }
  paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
}

#' Serialize a column transform to a name string
#' @noRd
column_transform_to_name <- function(transform) {
  type <- attr(transform, 'transform_type')
  p <- attr(transform, 'params')
  switch(
    type,
    'il_substr' = paste0('il_substr(', p$start, ',', p$length, ')'),
    'il_regex_extract' = paste0(
      'il_regex_extract("',
      p$pattern,
      '",',
      p$group,
      ')'
    ),
    'il_nullif' = paste0('il_nullif("', p$value, '")'),
    'il_cast_to_string' = 'il_cast_to_string()',
    'il_try_parse_date' = paste0('il_try_parse_date("', p$format, '")'),
    'il_try_parse_timestamp' = paste0(
      'il_try_parse_timestamp("',
      p$format,
      '")'
    ),
    'il_array_element' = paste0('il_array_element("', p$position, '")'),
    NA_character_
  )
}
