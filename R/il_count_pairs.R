#' Count Candidate Pairs Under Blocking Rules
#'
#' Estimates how many record pairs each blocking rule generates without
#' performing full comparisons. Useful for tuning blocking strategies
#' before training — too many pairs is slow; too few misses matches.
#'
#' @param .data A data frame or tibble (first or only dataset).
#' @param ... Blocking rules created by [block_on()], and optionally
#'   additional data frames for linkage.
#' @param con A DBI connection object used for computation.
#' @param link_type One of `"dedupe"` (default) or `"link"`.
#'
#' @return A tibble with columns `rule`, `pairs_generated`,
#'   `cumulative_pairs`, and `pct_of_cartesian`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_count_pairs(
#'   voters_2020, voters_2024,
#'   block_on(state),
#'   block_on(first_name),
#'   con = con,
#'   link_type = "link"
#' )
#' }
il_count_pairs <- function(.data, ..., con,
                           link_type = c("dedupe", "link")) {
  cli::cli_warn("Function {.fn il_count_pairs} is not yet implemented.")
  invisible(NULL)
}
