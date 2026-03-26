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

  existing <- DBI::dbReadTable(con, model$data$tbl_l)
  all_results <- list()

  mu <- extract_mu_vectors(params, comp_names)
  n_comp <- length(comparisons)

  for (i in seq_len(nrow(new_records))) {
    new_rec <- new_records[i, , drop = FALSE]
    candidates <- existing

    if (length(blocking_rules) > 0L) {
      keep <- rep(FALSE, nrow(candidates))
      for (br in blocking_rules) {
        rule_match <- rep(TRUE, nrow(candidates))
        for (col in br$columns) {
          if (col %in% names(new_rec) && col %in% names(candidates)) {
            rule_match <- rule_match &
              !is.na(candidates[[col]]) &
              !is.na(new_rec[[col]][1]) &
              candidates[[col]] == new_rec[[col]][1]
          } else {
            rule_match <- rep(FALSE, nrow(candidates))
          }
        }
        keep <- keep | rule_match
      }
      candidates <- candidates[keep, , drop = FALSE]
    }

    if (nrow(candidates) == 0L) next

    # Build pairs using only columns needed for comparisons
    n_cand <- nrow(candidates)
    pairs <- data.frame(row.names = seq_len(n_cand))
    for (col in comp_cols) {
      if (col %in% names(new_rec)) {
        pairs[[paste0("l_", col)]] <- rep(new_rec[[col]][1], n_cand)
      } else {
        pairs[[paste0("l_", col)]] <- rep(NA_character_, n_cand)
      }
      pairs[[paste0("r_", col)]] <- candidates[[col]]
    }

    gamma_mat <- compute_gamma_matrix(pairs, comparisons)
    match_weight <- score_gamma_matrix(gamma_mat, mu)
    match_probability <- weight_to_probability(match_weight, prior)

    res <- tibble::tibble(
      unique_id_r = candidates$unique_id,
      match_weight = match_weight,
      match_probability = match_probability
    )
    res <- res[res$match_probability >= threshold, , drop = FALSE]
    if (nrow(res) > 0L) all_results <- c(all_results, list(res))
  }

  if (length(all_results) == 0L) {
    return(tibble::tibble(
      unique_id_r = integer(0),
      match_weight = numeric(0),
      match_probability = numeric(0)
    ))
  }

  do.call(rbind, all_results)
}
