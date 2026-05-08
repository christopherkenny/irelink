#' Phonetic Transform Functions
#'
#' Phonetic algorithms for blocking and comparison transforms. These
#' functions compute phonetic encodings that group similar-sounding
#' names together. They are useful for blocking rules that tolerate
#' spelling variation.
#'
#' When used as a `transform` argument in [il_block_on()], [block_on()],
#' or [il_compare()], the computation is pushed into SQL so data is
#' never materialized into R.
#'
#' @param x A character vector to encode.
#'
#' @details
#' ## SQL availability
#'
#' | Function        | DuckDB        | PostgreSQL      | SQLite                    |
#' |-----------------|---------------|-----------------|---------------------------|
#' | `il_soundex`    | ✓ (macro)     | ✓ (native)      | comparisons only (R-side) |
#' | `il_metaphone`  | ✗             | ✓ (native)      | ✗                         |
#' | `il_dmetaphone` | ✗             | ✓ (native)      | ✗                         |
#'
#' SQLite does not expose a way to register scalar R functions as SQL UDFs,
#' so phonetic transforms cannot be used in **blocking rules** on SQLite.
#' They continue to work in **comparisons** on SQLite via the R-side gamma
#' computation path.
#'
#' @return A character vector of phonetic codes (same length as `x`).
#' @name phonetic
#' @examples
#' il_soundex(c('Smith', 'Smyth'))
#' il_soundex(c('Robert', 'Rupert'))
NULL

#' @rdname phonetic
#' @export
il_soundex <- function(x) {
  vapply(x, soundex_one, character(1), USE.NAMES = FALSE)
}

#' @rdname phonetic
#' @export
il_metaphone <- function(x) {
  cli::cli_abort(c(
    '{.fn il_metaphone} is only available as a SQL transform (PostgreSQL).',
    'i' = 'Use it as {.code transform = il_metaphone} in {.fn il_block_on} or {.fn il_compare}.'
  ))
}

#' @rdname phonetic
#' @export
il_dmetaphone <- function(x) {
  cli::cli_abort(c(
    '{.fn il_dmetaphone} is only available as a SQL transform (PostgreSQL).',
    'i' = 'Use it as {.code transform = il_dmetaphone} in {.fn il_block_on} or {.fn il_compare}.'
  ))
}

# R-side Soundex implementation
# Follows the standard algorithm: retain first letter, map consonants to
# digits, collapse adjacent duplicates while treating H/W as transparent
# separators, and pad/truncate to 4 characters.
soundex_one <- function(s) {
  if (is.na(s) || nchar(s) == 0L) {
    return(NA_character_)
  }
  s <- toupper(s)
  first <- substr(s, 1L, 1L)
  chars <- strsplit(s, '')[[1L]]

  # Soundex code map
  codes <- c(
    A = '0', B = '1', C = '2', D = '3', E = '0', F = '1', G = '2',
    H = '0', I = '0', J = '2', K = '2', L = '4', M = '5', N = '5',
    O = '0', P = '1', Q = '2', R = '6', S = '2', T = '3', U = '0',
    V = '1', W = '0', X = '2', Y = '0', Z = '2'
  )
  vowels <- c('A', 'E', 'I', 'O', 'U', 'Y')
  separators <- c('H', 'W')

  last_code <- unname(codes[first])
  out <- character(0)
  if (length(chars) > 1L) {
    for (ch in chars[-1L]) {
      if (ch %in% separators) {
        next
      }
      code <- unname(codes[ch])
      if (is.na(code) || ch %in% vowels) {
        last_code <- NULL
        next
      }
      if (!identical(code, last_code)) {
        out <- c(out, code)
      }
      last_code <- code
    }
  }

  code <- paste0(first, paste0(out, collapse = ''))
  # Pad to 4 characters
  code <- paste0(code, '000')
  substr(code, 1L, 4L)
}


# ---- DuckDB macro registration ----

#' Register phonetic SQL macros on a DuckDB connection
#'
#' Creates `il_soundex` as a DuckDB MACRO so that phonetic blocking
#' runs entirely inside the database engine.
#'
#' @param con A DBI connection to DuckDB.
#' @noRd
register_phonetic_macros <- function(con) {
  dialect <- detect_dialect(con)
  if (dialect != 'duckdb') {
    return(invisible(NULL))
  }

  letters_only <- "regexp_replace(upper(CAST(s AS VARCHAR)), '[^A-Z]', '', 'g')"
  first_letter <- paste0('substr(', letters_only, ', 1, 1)')
  first_code <- paste0(
    'translate(', first_letter, ', ',
    "'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '01230120022455012623010202')"
  )
  coded_tail <- paste0(
    'translate(',
    "replace(replace(substr(", letters_only, ", 2), 'H', ''), 'W', '')",
    ", 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', '01230120022455012623010202')"
  )
  dedup <- dedup_adjacent(coded_tail)
  trimmed <- paste0(
    'CASE WHEN left(', dedup, ', 1) = ', first_code,
    ' THEN substr(', dedup, ', 2) ELSE ', dedup, ' END'
  )

  macro_sql <- paste0(
    'CREATE OR REPLACE MACRO il_soundex(s) AS (',
    'CASE WHEN s IS NULL OR length(', letters_only, ') = 0 THEN NULL ELSE ',
    'left(', first_letter, " || replace((", trimmed, "), '0', '') || '000', 4) ",
    'END)'
  )
  DBI::dbExecute(con, macro_sql)
  invisible(NULL)
}

# Helper: wrap an expression in nested replace() calls that collapse
# adjacent duplicate digits (0–6). Repeated passes handle longer runs.
dedup_adjacent <- function(expr, passes = 4L) {
  for (i in seq_len(passes)) {
    for (d in as.character(0:6)) {
      dd <- paste0(d, d)
      expr <- paste0('replace(', expr, ", '", dd, "', '", d, "')")
    }
  }
  expr
}
