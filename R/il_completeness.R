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
  dfs <- list(...)
  results <- list()

  for (i in seq_along(dfs)) {
    df <- dfs[[i]]
    tbl_name <- paste0("__il_completeness_", i)
    DBI::dbWriteTable(con, tbl_name, df, overwrite = TRUE)
    on.exit(DBI::dbRemoveTable(con, tbl_name, fail_if_missing = FALSE), add = TRUE)

    n_total <- nrow(df)
    col_names <- names(df)

    rows <- lapply(col_names, function(col_nm) {
      sql <- sprintf(
        "SELECT COUNT(%s) AS n_non_null FROM %s",
        DBI::dbQuoteIdentifier(con, col_nm),
        DBI::dbQuoteIdentifier(con, tbl_name)
      )
      res <- DBI::dbGetQuery(con, sql)
      tibble::tibble(
        table = paste0("table_", i),
        column = col_nm,
        n_total = n_total,
        n_non_null = as.integer(res$n_non_null),
        pct_non_null = as.numeric(res$n_non_null) / n_total * 100
      )
    })

    results <- c(results, rows)
  }

  do.call(rbind, results)
}
