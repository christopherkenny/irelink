#' Personal Name Comparison
#'
#' A pre-built domain comparison for personal names. Combines exact
#' matching, Jaro-Winkler, and Jaro levels with thresholds tuned for
#' typical name variation.
#'
#' @param ... Reserved for future options.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_name())
cl_name <- function(...) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_jaro_winkler(0.92),
    cl_jaro_winkler(0.88),
    cl_jaro_winkler(0.7),
    cl_else()
  )
}

#' Date of Birth Comparison
#'
#' A pre-built domain comparison for dates of birth. Combines
#' string-parsing, date-difference, and component-matching levels to
#' handle common date-of-birth errors (transpositions, partial dates).
#'
#' @param ... Reserved for future options.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(dob, cl_dob())
cl_dob <- function(...) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_damerau_levenshtein(1),
    cl_date_diff(months(1)),
    cl_date_diff(years(1)),
    cl_date_diff(years(10)),
    cl_else()
  )
}

#' Email Address Comparison
#'
#' A pre-built domain comparison for email addresses. Provides levels for
#' exact match, username-only match, and domain-only match.
#'
#' @param ... Reserved for future options.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(email, cl_email())
cl_email <- function(...) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom("LOWER(SUBSTR(l.{col}, 1, INSTR(l.{col}, '@') - 1)) = LOWER(SUBSTR(r.{col}, 1, INSTR(r.{col}, '@') - 1))"),
    cl_jaro_winkler(0.88),
    cl_custom("LOWER(SUBSTR(l.{col}, INSTR(l.{col}, '@'), LENGTH(l.{col}))) = LOWER(SUBSTR(r.{col}, INSTR(r.{col}, '@'), LENGTH(r.{col})))"),
    cl_else()
  )
}

#' Forename and Surname Comparison with Swap Detection
#'
#' A pre-built domain comparison that compares forename and surname
#' columns, including a cross-field swap-detection level (where first name
#' and surname are accidentally transposed).
#'
#' @param ... Reserved for future options.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(first_name, cl_forename_surname())
cl_forename_surname <- function(...) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom('l.{col_forename} = r.{col_surname} AND l.{col_surname} = r.{col_forename}'),
    cl_jaro_winkler(0.92),
    cl_jaro_winkler(0.88),
    cl_custom('l.{col_forename} = r.{col_forename}'),
    cl_else()
  )
}

#' Postcode Comparison
#'
#' A pre-built domain comparison for postcodes. Supports exact matching
#' with optional geographic-proximity fallback for partial matches.
#'
#' @param ... Reserved for future options (e.g., geographic fallback).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(postcode, cl_postcode())
cl_postcode <- function(...) {
  cl_levels(
    cl_null(),
    cl_exact(),
    cl_custom('SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 1) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 1)'),
    cl_custom('SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 2) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 2)'),
    cl_custom('SUBSTR(l.{col}, 1, LENGTH(l.{col}) - 3) = SUBSTR(r.{col}, 1, LENGTH(r.{col}) - 3)'),
    cl_else()
  )
}
