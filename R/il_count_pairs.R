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
  link_type <- match.arg(link_type)
  dots <- list(...)

  # Separate blocking rules from extra data frames
  blocking_rules <- list()
  extra_dfs <- list()
  for (d in dots) {
    if (inherits(d, "il_blocking_rule")) {
      blocking_rules <- c(blocking_rules, list(d))
    } else if (is.data.frame(d)) {
      extra_dfs <- c(extra_dfs, list(d))
    }
  }

  tbl_l <- "__il_pairs_l"
  DBI::dbWriteTable(con, tbl_l, .data, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, tbl_l, fail_if_missing = FALSE), add = TRUE)

  if (link_type == "link" && length(extra_dfs) > 0L) {
    tbl_r <- "__il_pairs_r"
    DBI::dbWriteTable(con, tbl_r, extra_dfs[[1]], overwrite = TRUE)
    on.exit(DBI::dbRemoveTable(con, tbl_r, fail_if_missing = FALSE), add = TRUE)
  } else {
    tbl_r <- tbl_l
  }

  if (length(blocking_rules) == 0L) {
    # Cartesian count
    if (link_type == "dedupe") {
      n <- nrow(.data)
      n_pairs <- as.integer(n * (n - 1L) / 2L)
    } else {
      n_pairs <- as.integer(nrow(.data) * nrow(extra_dfs[[1]]))
    }
    return(tibble::tibble(rule = "cartesian", n_pairs = n_pairs))
  }

  results <- lapply(blocking_rules, function(rule) {
    cols <- rule$columns
    where <- build_blocking_condition(cols)
    n <- count_blocked_pairs(con, tbl_l, tbl_r, where,
                             dedupe = (link_type == "dedupe"))
    tibble::tibble(
      rule = paste(cols, collapse = " & "),
      n_pairs = as.integer(n)
    )
  })

  do.call(rbind, results)
}
