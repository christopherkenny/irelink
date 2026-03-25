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
#' \dontrun{
#' il_spec() |>
#'   il_compare(first_name, cl_name())
#' }
cl_name <- function(...) {
  cli::cli_warn("Function {.fn cl_name} is not yet implemented.")
  invisible(NULL)
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
#' \dontrun{
#' il_spec() |>
#'   il_compare(dob, cl_dob())
#' }
cl_dob <- function(...) {
  cli::cli_warn("Function {.fn cl_dob} is not yet implemented.")
  invisible(NULL)
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
#' \dontrun{
#' il_spec() |>
#'   il_compare(email, cl_email())
#' }
cl_email <- function(...) {
  cli::cli_warn("Function {.fn cl_email} is not yet implemented.")
  invisible(NULL)
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
#' \dontrun{
#' il_spec() |>
#'   il_compare(first_name, cl_forename_surname())
#' }
cl_forename_surname <- function(...) {
  cli::cli_warn("Function {.fn cl_forename_surname} is not yet implemented.")
  invisible(NULL)
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
#' \dontrun{
#' il_spec() |>
#'   il_compare(postcode, cl_postcode())
#' }
cl_postcode <- function(...) {
  cli::cli_warn("Function {.fn cl_postcode} is not yet implemented.")
  invisible(NULL)
}
