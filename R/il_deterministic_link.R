#' Deterministic Record Linkage
#'
#' Finds exact-match record pairs using the blocking rules in the
#' specification, without requiring probabilistic training. This is a
#' common first step before probabilistic linkage — pairs that match on
#' all blocking columns are returned directly.
#'
#' @param .data A data frame or tibble (first or only dataset).
#' @param ... Additional data frames for multi-table linkage.
#' @param spec An `il_spec` object with blocking rules defined via
#'   [il_block_on()].
#' @param con A DBI connection object.
#' @param link_type One of `"dedupe"` (default), `"link"`, or
#'   `"link_and_dedupe"`.
#'
#' @return A tibble of exact-match record pairs.
#' @export
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_block_on(first_name, surname, dob)
#'
#' exact_matches <- il_deterministic_link(
#'   voters, spec = spec, con = con
#' )
#' }
il_deterministic_link <- function(.data, ..., spec, con,
                                  link_type = c("dedupe", "link",
                                                "link_and_dedupe")) {
  link_type <- match.arg(link_type)
  validate_il_spec(spec)

  .data <- factor_to_char(.data)
  comparisons <- spec$comparisons
  blocking_rules <- spec$blocking_rules

  tbl_name <- "__il_det_data"
  DBI::dbWriteTable(con, tbl_name, .data, overwrite = TRUE)
  on.exit(try(DBI::dbRemoveTable(con, tbl_name), silent = TRUE))

  cols <- names(.data)
  sel <- build_select_aliases(cols)

  if (length(blocking_rules) > 0L) {
    block_sqls <- vapply(blocking_rules, function(br) {
      paste0("(", build_blocking_condition(br$columns), ")")
    }, character(1))
    block_where <- paste(block_sqls, collapse = " OR ")
  } else {
    block_where <- "1 = 1"
  }

  sql <- sprintf(
    "SELECT %s, %s FROM %s l, %s r WHERE l.rowid < r.rowid AND %s",
    sel$left, sel$right, tbl_name, tbl_name, block_where
  )
  pairs <- DBI::dbGetQuery(con, sql)

  if (nrow(pairs) == 0L) {
    return(tibble::tibble(unique_id_l = integer(0), unique_id_r = integer(0)))
  }

  # Keep only pairs where ALL comparison columns match exactly
  keep <- rep(TRUE, nrow(pairs))
  for (comp in comparisons) {
    col <- comp$columns
    val_l <- pairs[[paste0("l_", col)]]
    val_r <- pairs[[paste0("r_", col)]]
    keep <- keep & !is.na(val_l) & !is.na(val_r) & val_l == val_r
  }
  pairs <- pairs[keep, , drop = FALSE]

  tibble::tibble(
    unique_id_l = pairs$l_unique_id,
    unique_id_r = pairs$r_unique_id
  )
}
