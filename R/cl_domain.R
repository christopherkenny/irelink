#' Soundex Phonetic Comparison
#'
#' Creates a comparison level based on the Soundex phonetic algorithm.
#' Two strings match if their Soundex codes are identical. This can be
#' used as a fallback level within [cl_levels()] or [cl_name()] to catch
#' names that sound similar but are spelled differently (e.g.,
#' Smith/Smyth, Robert/Rupert).
#'
#' On DuckDB, Soundex runs via a registered SQL MACRO.
#' On SQLite, it falls back to an R-side implementation.
#'
#' @return A comparison-level object for use in [il_compare()] or
#'   [cl_levels()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_soundex())
#'
#' il_spec() |>
#'   il_compare(
#'     first_name,
#'     cl_levels(
#'       cl_null(),
#'       cl_exact(),
#'       cl_jaro_winkler(0.9),
#'       cl_soundex(),
#'       cl_else()
#'     )
#'   )
cl_soundex <- function() {
  new_comparison_level('soundex')
}

#' Personal Name Comparison
#'
#' A pre-built domain comparison for personal names. Combines exact
#' matching and Jaro-Winkler levels with thresholds tuned for typical
#' name variation. Optionally adds a Soundex phonetic level as a final
#' fallback before the else level, which helps catch names that sound
#' similar but are spelled differently (e.g., Smith/Smyth).
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   name frequency at the highest comparison level. Defaults to `FALSE`.
#' @param phonetic Logical. If `TRUE`, add a [cl_soundex()] level as a
#'   fallback before the else level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_name()) |>
#'   il_compare(surname, cl_name(term_frequency = TRUE))
#'
#' il_spec() |>
#'   il_compare(first_name, cl_name(phonetic = TRUE))
cl_name <- function(term_frequency = FALSE, phonetic = FALSE) {
  if (phonetic) {
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_jaro_winkler(0.92),
      cl_jaro_winkler(0.88),
      cl_jaro_winkler(0.7),
      cl_soundex(),
      cl_else(),
      term_frequency = term_frequency
    )
  } else {
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_jaro_winkler(0.92),
      cl_jaro_winkler(0.88),
      cl_jaro_winkler(0.7),
      cl_else(),
      term_frequency = term_frequency
    )
  }
}

#' Date of Birth Comparison
#'
#' A pre-built domain comparison for dates of birth. Combines exact
#' matching, a Damerau-Levenshtein string check for transposed digits,
#' and configurable date-difference levels to handle common errors.
#'
#' @param thresholds A list of unit-tagged threshold values created by
#'   [days()], [months()], or [years()], ordered from strictest to most
#'   lenient. Defaults to `list(months(1), years(1), years(10))`.
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   date-of-birth frequency at the highest comparison level. Defaults
#'   to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(dob, cl_dob())
#'
#' # Custom thresholds: within 7 days, 6 months, 2 years
#' il_spec() |>
#'   il_compare(dob, cl_dob(thresholds = list(days(7), months(6), years(2))))
cl_dob <- function(
  thresholds = list(months(1), years(1), years(10)),
  term_frequency = FALSE
) {
  if (!is.list(thresholds) || length(thresholds) == 0L) {
    cli::cli_abort(
      '{.arg thresholds} must be a non-empty list of unit-tagged values, ',
      'e.g., {.code list(months(1), years(1))}.'
    )
  }
  date_levels <- lapply(thresholds, function(t) cl_date_diff(t))
  base_levels <- c(
    list(cl_null(), cl_exact(), cl_damerau_levenshtein(1)),
    date_levels,
    list(cl_else())
  )
  do.call(cl_levels, c(base_levels, list(term_frequency = term_frequency)))
}

#' Email Address Comparison
#'
#' A pre-built domain comparison for email addresses. Provides levels for
#' exact match, username-only match, and domain-only match.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   email frequency at the highest comparison level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(email, cl_email())
cl_email <- function(term_frequency = FALSE) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom(
      "LOWER(SUBSTR(l.{col}, 1, INSTR(l.{col}, '@') - 1)) = LOWER(SUBSTR(r.{col}, 1, INSTR(r.{col}, '@') - 1))"
    ),
    cl_jaro_winkler(0.88),
    cl_custom(
      "LOWER(SUBSTR(l.{col}, INSTR(l.{col}, '@'), LENGTH(l.{col}))) = LOWER(SUBSTR(r.{col}, INSTR(r.{col}, '@'), LENGTH(r.{col})))"
    ),
    cl_else(),
    term_frequency = term_frequency
  )
}

#' Forename and Surname Comparison with Swap Detection
#'
#' A pre-built domain comparison that compares forename and surname
#' columns, including a cross-field swap-detection level (where first name
#' and surname are accidentally transposed). Pass this to
#' [il_compare()] on the forename/first-name column and supply the
#' companion surname/last-name column via `surname`.
#'
#' See also [cl_first_last_name()] for an American-English alias.
#'
#' @param surname Name of the surname column in the data. Defaults to
#'   `'surname'`.
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   name frequency at the highest comparison level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_forename_surname(surname = 'last_name'))
cl_forename_surname <- function(surname = 'surname', term_frequency = FALSE) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_columns_reversed(surname, symmetrical = TRUE),
    cl_jaro_winkler(0.92),
    cl_jaro_winkler(0.88),
    cl_else(),
    term_frequency = term_frequency
  )
}

#' First Name and Last Name Comparison with Swap Detection
#'
#' An American-English alias for [cl_forename_surname()]. Compares first
#' and last name columns, including a swap-detection level for accidentally
#' transposed names. Pass this to [il_compare()] on the first-name column
#' and supply the companion last-name column via `last_name`.
#'
#' @param last_name Name of the last name column in the data. Defaults to
#'   `'last_name'`.
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   name frequency at the highest comparison level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_first_last_name())
cl_first_last_name <- function(
  last_name = 'last_name',
  term_frequency = FALSE
) {
  cl_forename_surname(surname = last_name, term_frequency = term_frequency)
}

#' Postcode Comparison
#'
#' A pre-built domain comparison for postcodes. Supports exact matching
#' and prefix-based partial matching. Optionally appends geographic
#' distance fallback levels when latitude and longitude columns are
#' available.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   postcode frequency at the highest comparison level. Defaults to
#'   `FALSE`.
#' @param lat_col,long_col Character. Names of latitude and longitude
#'   columns. Both must be supplied together. When provided, geographic
#'   distance levels are appended before `cl_else()`.
#' @param km_thresholds Numeric vector of distance thresholds in
#'   kilometres, ordered from strictest to most lenient. Only used when
#'   `lat_col` and `long_col` are supplied. Defaults to `c(1, 10, 100)`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(postcode, cl_postcode())
#'
#' # With geographic fallback (requires lat/lon columns in the data)
#' il_spec() |>
#'   il_compare(postcode, cl_postcode(lat_col = 'lat', long_col = 'lon'))
cl_postcode <- function(
  term_frequency = FALSE,
  lat_col = NULL,
  long_col = NULL,
  km_thresholds = c(1, 10, 100)
) {
  if (!is.null(lat_col) && !is.null(long_col)) {
    geo_levels <- geo_distance_levels(lat_col, long_col, sort(km_thresholds))
    do.call(
      cl_levels,
      c(
        list(
          cl_null(),
          cl_exact(),
          cl_custom(
            'SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 1) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 1)'
          ),
          cl_custom(
            'SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 2) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 2)'
          ),
          cl_custom(
            'SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 3) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 3)'
          )
        ),
        geo_levels,
        list(cl_else(), term_frequency = term_frequency)
      )
    )
  } else {
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_custom(
        'SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 1) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 1)'
      ),
      cl_custom(
        'SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 2) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 2)'
      ),
      cl_custom(
        'SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 3) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 3)'
      ),
      cl_else(),
      term_frequency = term_frequency
    )
  }
}

#' ZIP Code Comparison
#'
#' A pre-built domain comparison for US ZIP codes. Provides levels for
#' exact match, 5-digit prefix match (normalizes ZIP+4 against plain
#' 5-digit codes), and 3-digit Sectional Center Facility (SCF) prefix
#' match. Accepts both plain 5-digit (`'90210'`) and ZIP+4
#' (`'90210-3456'`) formats. Optionally appends geographic distance
#' fallback levels when latitude and longitude columns are available.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   ZIP code frequency at the highest comparison level. Defaults to
#'   `FALSE`.
#' @param lat_col,long_col Character. Names of latitude and longitude
#'   columns. Both must be supplied together. When provided, geographic
#'   distance levels are appended before `cl_else()`.
#' @param km_thresholds Numeric vector of distance thresholds in
#'   kilometres, ordered from strictest to most lenient. Only used when
#'   `lat_col` and `long_col` are supplied. Defaults to `c(1, 10, 100)`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(zip, cl_zip_code())
#'
#' # With geographic fallback (requires lat/lon columns in the data)
#' il_spec() |>
#'   il_compare(zip, cl_zip_code(lat_col = 'lat', long_col = 'lon'))
cl_zip_code <- function(
  term_frequency = FALSE,
  lat_col = NULL,
  long_col = NULL,
  km_thresholds = c(1, 10, 100)
) {
  if (!is.null(lat_col) && !is.null(long_col)) {
    geo_levels <- geo_distance_levels(lat_col, long_col, sort(km_thresholds))
    do.call(
      cl_levels,
      c(
        list(
          cl_null(),
          cl_exact(),
          cl_custom('SUBSTR(l.{col}, 1, 5) = SUBSTR(r.{col}, 1, 5)'),
          cl_custom('SUBSTR(l.{col}, 1, 3) = SUBSTR(r.{col}, 1, 3)')
        ),
        geo_levels,
        list(cl_else(), term_frequency = term_frequency)
      )
    )
  } else {
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_custom('SUBSTR(l.{col}, 1, 5) = SUBSTR(r.{col}, 1, 5)'),
      cl_custom('SUBSTR(l.{col}, 1, 3) = SUBSTR(r.{col}, 1, 3)'),
      cl_else(),
      term_frequency = term_frequency
    )
  }
}

# Internal helper: build a list of cl_custom() levels for Haversine distance
# thresholds between lat/lon columns. Each level checks whether the great-circle
# distance between the two records is within `d` km.
geo_distance_levels <- function(lat_col, long_col, km_thresholds) {
  lapply(km_thresholds, function(d) {
    sql <- paste0(
      'l.',
      lat_col,
      ' IS NOT NULL AND r.',
      lat_col,
      ' IS NOT NULL AND ',
      'l.',
      long_col,
      ' IS NOT NULL AND r.',
      long_col,
      ' IS NOT NULL AND ',
      '2 * 6371 * ASIN(SQRT(',
      'POWER(SIN(RADIANS((r.',
      lat_col,
      ' - l.',
      lat_col,
      ') / 2)), 2) + ',
      'COS(RADIANS(l.',
      lat_col,
      ')) * COS(RADIANS(r.',
      lat_col,
      ')) * ',
      'POWER(SIN(RADIANS((r.',
      long_col,
      ' - l.',
      long_col,
      ') / 2)), 2)',
      ')) <= ',
      d
    )
    cl_custom(sql)
  })
}
