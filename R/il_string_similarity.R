#' Compute String Similarity Scores
#'
#' Computes multiple string-similarity metrics between two strings in a
#' single call. No database connection is required. Useful for quick
#' exploration of how names or other text fields compare.
#'
#' @param a A character string.
#' @param b A character string.
#'
#' @return A single-row tibble with columns `jaro`, `jaro_winkler`,
#'   `levenshtein`, `damerau_levenshtein`, and `jaccard`.
#' @export
#'
#' @examples
#' il_string_similarity('John', 'Jon')
il_string_similarity <- function(a, b) {
  if (!is.character(a) || !is.character(b)) {
    cli::cli_abort('{.arg a} and {.arg b} must be character strings.')
  }
  if (length(a) != 1L || length(b) != 1L) {
    cli::cli_abort('{.arg a} and {.arg b} must each be a single string.')
  }

  if (is.na(a) || is.na(b)) {
    return(tibble::tibble(
      jaro_winkler = NA_real_,
      jaro = NA_real_,
      levenshtein = NA_integer_,
      jaccard = NA_real_,
      cosine = NA_real_
    ))
  }

  jw <- 1 - stringdist::stringdist(a, b, method = 'jw', p = 0.1)
  j <- 1 - stringdist::stringdist(a, b, method = 'jw', p = 0)
  lv <- as.integer(stringdist::stringdist(a, b, method = 'lv'))
  jac <- 1 - stringdist::stringdist(a, b, method = 'jaccard', q = 2)
  cos <- 1 - stringdist::stringdist(a, b, method = 'cosine', q = 2)

  tibble::tibble(
    jaro_winkler = jw,
    jaro = j,
    levenshtein = lv,
    jaccard = jac,
    cosine = cos
  )
}
