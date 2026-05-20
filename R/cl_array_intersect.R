#' Array Intersection Comparison
#'
#' Creates comparison levels based on the number of shared elements
#' between two array or list columns. Thresholds are integer counts,
#' ordered from strictest (most shared elements required) to most lenient.
#'
#' @param ... Integer count thresholds, ordered from strictest to most
#'   lenient (e.g., `2, 1`).
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(tags, cl_array_intersect(2, 1))
cl_array_intersect <- function(...) {
  thresholds <- c(...)
  if (length(thresholds) == 0L) {
    cli::cli_abort('{.fn cl_array_intersect} requires at least one threshold.')
  }
  if (!is.numeric(thresholds) || anyNA(thresholds)) {
    cli::cli_abort('Thresholds for {.fn cl_array_intersect} must be numeric.')
  }
  if (any(thresholds < 0)) {
    cli::cli_abort(
      'Thresholds for {.fn cl_array_intersect} must be non-negative.'
    )
  }
  if (length(thresholds) > 1L && is.unsorted(rev(thresholds))) {
    cli::cli_warn(
      'Thresholds for {.fn cl_array_intersect} should be in descending order; re-ordering.'
    )
    thresholds <- sort(thresholds, decreasing = TRUE)
  }
  new_comparison_level('array_intersect', thresholds = thresholds)
}

#' Pairwise Array Minimum Distance Comparison
#'
#' Creates comparison levels based on the best-matching pair of values
#' across two array columns. For each record pair, every element of the
#' left array is compared against every element of the right array. The
#' best score (maximum similarity for `'jaro_winkler'`, minimum distance
#' for `'levenshtein'`) is then tested against each threshold.
#'
#' On DuckDB the pairwise comparison runs in SQL via an UNNEST cross-join
#' scalar subquery. On SQLite it falls back to an R-side nested apply.
#'
#' @param fn Distance function: `'jaro_winkler'` (default) or
#'   `'levenshtein'`. For `'jaro_winkler'`, thresholds are similarity
#'   scores (0–1, descending, strictest first). For `'levenshtein'`,
#'   thresholds are edit distances (non-negative integers, ascending,
#'   strictest first).
#' @param ... Numeric thresholds, from strictest to most lenient.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' # Jaro-Winkler: best pairwise similarity >= 0.9 or >= 0.7
#' il_spec() |>
#'   il_compare(aliases, cl_array_min_distance('jaro_winkler', 0.9, 0.7))
#'
#' # Levenshtein: best pairwise edit distance <= 1 or <= 2
#' il_spec() |>
#'   il_compare(aliases, cl_array_min_distance('levenshtein', 1, 2))
cl_array_min_distance <- function(fn = c('jaro_winkler', 'levenshtein'), ...) {
  fn <- match.arg(fn)
  thresholds <- c(...)
  if (length(thresholds) == 0L) {
    cli::cli_abort('{.arg ...} must include at least one threshold.')
  }
  if (fn == 'jaro_winkler') {
    if (any(thresholds < 0 | thresholds > 1)) {
      cli::cli_abort('Jaro-Winkler thresholds must be between 0 and 1.')
    }
    if (is.unsorted(rev(thresholds))) {
      cli::cli_warn(
        'Jaro-Winkler thresholds should be in descending order (strictest first).'
      )
    }
  } else {
    if (any(thresholds < 0)) {
      cli::cli_abort('Levenshtein thresholds must be non-negative.')
    }
    if (is.unsorted(thresholds)) {
      cli::cli_warn(
        'Levenshtein thresholds should be in ascending order (strictest first).'
      )
    }
  }
  new_comparison_level('array_min_distance', fn = fn, thresholds = thresholds)
}

#' Array Subset Comparison
#'
#' Creates a comparison level that matches when the smaller of two array
#' columns is a complete subset of the larger. In other words, every
#' element of the smaller array appears in the larger one.
#'
#' On DuckDB and PostgreSQL this is computed in SQL using
#' `ARRAY_LENGTH(ARRAY_INTERSECT(...)) = LEAST(ARRAY_LENGTH(...))`.
#' On SQLite it falls back to an R-side set check.
#'
#' @return A comparison-level object for use in [il_compare()].
#' @export
#'
#' @examples
#' il_spec() |>
#'   il_compare(qualifications, cl_array_subset())
cl_array_subset <- function() {
  new_comparison_level('array_subset')
}
