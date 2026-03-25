#' Column Completeness Across Datasets
#'
#' Computes the percentage of non-null values for each column across one
#' or more data frames. Returns a tidy tibble suitable for plotting with
#' [ggplot2::geom_col()].
#'
#' @param ... One or more data frames or tibbles to profile.
#' @param con A DBI connection object used for computation.
#'
#' @return A tibble with columns `table`, `column`, `n_total`,
#'   `n_non_null`, and `pct_non_null`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_completeness(voters_2020, voters_2024, con = con) |>
#'   ggplot2::ggplot(ggplot2::aes(x = column, y = pct_non_null, fill = table)) +
#'   ggplot2::geom_col(position = "dodge") +
#'   ggplot2::coord_flip()
#' }
il_completeness <- function(..., con) {
  cli::cli_warn("Function {.fn il_completeness} is not yet implemented.")
  invisible(NULL)
}
