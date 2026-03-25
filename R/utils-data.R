# Internal helpers for data manipulation

#' Convert factor columns to character
#' @param df A data frame.
#' @return The data frame with factors converted to character.
#' @noRd
factor_to_char <- function(df) {
  factor_cols <- vapply(df, is.factor, logical(1))
  if (any(factor_cols)) {
    df[factor_cols] <- lapply(df[factor_cols], as.character)
  }
  df
}

#' Extract column names referenced in a spec's comparisons and blocking rules
#' @param spec An il_spec object.
#' @return A character vector of column names.
#' @noRd
get_spec_columns <- function(spec) {
  comp_cols <- unlist(lapply(spec$comparisons, function(comp) comp$columns))
  block_cols <- unlist(lapply(spec$blocking_rules, function(rule) rule$columns))
  unique(c(comp_cols, block_cols))
}
