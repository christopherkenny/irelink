#' Find Matches for New Records
#'
#' Scores new records against the data already loaded into a trained
#' model. Useful for real-time or incremental matching where new records
#' arrive after the model has been trained.
#'
#' @param model A trained `il_model` object.
#' @param new_records A data frame of new records to match against the
#'   model's existing data.
#' @param threshold A numeric value between 0 and 1. Only matches at or
#'   above this probability are returned. Defaults to `0.85`.
#'
#' @return An `il_compared` tibble of scored pairs between new records
#'   and existing data.
#' @export
#'
#' @examples
#' \dontrun{
#' new_arrivals <- data.frame(
#'   first_name = "Jane", surname = "Doe", dob = "1992-05-10"
#' )
#' il_find_matches(model, new_arrivals, threshold = 0.85)
#' }
il_find_matches <- function(model, new_records, threshold = 0.85) {
  validate_il_model(model)

  con <- model$con
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- model$params$prior %||% 0.05
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  blocking_rules <- model$spec$blocking_rules
  comp_cols <- unique(comp_names)

  mu <- extract_mu_vectors(params, comp_names)

  # Upload new records to a temporary table for SQL-side blocking
  new_records <- as.data.frame(new_records, stringsAsFactors = FALSE)
  if (!("unique_id" %in% names(new_records))) {
    new_records$unique_id <- paste0("new_", seq_len(nrow(new_records)))
  }
  tbl_new <- "__il_find_new"
  DBI::dbWriteTable(con, tbl_new, new_records, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, tbl_new, fail_if_missing = FALSE), add = TRUE)

  tbl_existing <- model$data$tbl_l

  # Only select columns that both tables share AND that are needed
  block_cols <- unique(unlist(lapply(blocking_rules, function(r) r$columns)))
  needed_cols <- unique(c("unique_id", comp_cols, block_cols))
  new_cols <- intersect(needed_cols, names(new_records))
  sel_l <- paste(sprintf("l.%s AS l_%s", new_cols, new_cols), collapse = ", ")
  sel_r <- paste(sprintf("r.%s AS r_%s", needed_cols, needed_cols), collapse = ", ")

  # Collect candidate pairs via SQL joins for each blocking rule
  all_pair_frames <- list()
  if (length(blocking_rules) > 0L) {
    for (br in blocking_rules) {
      block_where <- build_blocking_condition(br$columns)
      sql <- sprintf(
        "SELECT %s, %s FROM %s l, %s r WHERE %s",
        sel_l, sel_r, tbl_new, tbl_existing, block_where
      )
      bp <- DBI::dbGetQuery(con, sql)
      if (nrow(bp) > 0L) all_pair_frames <- c(all_pair_frames, list(bp))
    }
  } else {
    sql <- sprintf(
      "SELECT %s, %s FROM %s l, %s r",
      sel_l, sel_r, tbl_new, tbl_existing
    )
    bp <- DBI::dbGetQuery(con, sql)
    if (nrow(bp) > 0L) all_pair_frames <- list(bp)
  }

  if (length(all_pair_frames) == 0L) {
    return(tibble::tibble(
      unique_id_l = character(0),
      unique_id_r = character(0),
      match_weight = numeric(0),
      match_probability = numeric(0)
    ))
  }

  pairs <- do.call(rbind, all_pair_frames)
  pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = "||")
  pairs <- pairs[!duplicated(pair_key), , drop = FALSE]

  # Score all pairs in one batch
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  match_weight <- score_gamma_matrix(gamma_mat, mu)
  match_probability <- weight_to_probability(match_weight, prior)

  result <- tibble::tibble(
    unique_id_l = pairs$l_unique_id,
    unique_id_r = pairs$r_unique_id,
    match_weight = match_weight,
    match_probability = match_probability
  )
  result <- result[result$match_probability >= threshold, , drop = FALSE]

  if (nrow(result) == 0L) {
    return(tibble::tibble(
      unique_id_l = character(0),
      unique_id_r = character(0),
      match_weight = numeric(0),
      match_probability = numeric(0)
    ))
  }

  tibble::as_tibble(result)
}
