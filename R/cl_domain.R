#' Personal Name Comparison
#'
#' A pre-built domain comparison for personal names. Combines exact
#' matching, Jaro-Winkler, and Jaro levels with thresholds tuned for
#' typical name variation.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   name frequency at the highest comparison level. Defaults to `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_name()) |>
#'   il_compare(surname, cl_name(term_frequency = TRUE))
cl_name <- function(term_frequency = FALSE) {
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

#' Date of Birth Comparison
#'
#' A pre-built domain comparison for dates of birth. Combines
#' string-parsing, date-difference, and component-matching levels to
#' handle common date-of-birth errors (transpositions, partial dates).
#'
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
cl_dob <- function(term_frequency = FALSE) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_damerau_levenshtein(1),
    cl_date_diff(months(1)),
    cl_date_diff(years(1)),
    cl_date_diff(years(10)),
    cl_else(),
    term_frequency = term_frequency
  )
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
    cl_custom("LOWER(SUBSTR(l.{col}, 1, INSTR(l.{col}, '@') - 1)) = LOWER(SUBSTR(r.{col}, 1, INSTR(r.{col}, '@') - 1))"),
    cl_jaro_winkler(0.88),
    cl_custom("LOWER(SUBSTR(l.{col}, INSTR(l.{col}, '@'), LENGTH(l.{col}))) = LOWER(SUBSTR(r.{col}, INSTR(r.{col}, '@'), LENGTH(r.{col})))"),
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
  swap_sql <- paste0(
    'l.{col} = r.', surname, ' AND l.', surname, ' = r.{col}'
  )
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom(swap_sql),
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
cl_first_last_name <- function(last_name = 'last_name', term_frequency = FALSE) {
  cl_forename_surname(surname = last_name, term_frequency = term_frequency)
}

#' Postcode Comparison
#'
#' A pre-built domain comparison for postcodes. Supports exact matching
#' with optional geographic-proximity fallback for partial matches.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   postcode frequency at the highest comparison level. Defaults to
#'   `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(postcode, cl_postcode())
cl_postcode <- function(term_frequency = FALSE) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom('SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 1) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 1)'),
    cl_custom('SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 2) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 2)'),
    cl_custom('SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 3) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 3)'),
    cl_else(),
    term_frequency = term_frequency
  )
}

#' ZIP Code Comparison
#'
#' A pre-built domain comparison for US ZIP codes. Provides levels for
#' exact match, 5-digit prefix match (normalizes ZIP+4 against plain
#' 5-digit codes), and 3-digit Sectional Center Facility (SCF) prefix
#' match. Accepts both plain 5-digit (`'90210'`) and ZIP+4
#' (`'90210-3456'`) formats.
#'
#' @param term_frequency Logical. If `TRUE`, adjust match weights by
#'   ZIP code frequency at the highest comparison level. Defaults to
#'   `FALSE`.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(zip, cl_zip_code())
cl_zip_code <- function(term_frequency = FALSE) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom('SUBSTR(l.{col}, 1, 5) = SUBSTR(r.{col}, 1, 5)'),
    cl_custom('SUBSTR(l.{col}, 1, 3) = SUBSTR(r.{col}, 1, 3)'),
    cl_else(),
    term_frequency = term_frequency
  )
}
