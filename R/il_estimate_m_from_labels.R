#' Estimate Match (m) Parameters from Labelled Data
#'
#' Learns the m probabilities (the probability of observing each
#' comparison level given that the records **do** match) from a set of
#' pre-labelled record pairs. Use this instead of [il_estimate_em()] when
#' ground-truth labels are available.
#'
#' @param model An `il_model` object (piped in).
#' @param labels A data frame of labelled pairs with columns identifying
#'   the left record, right record, and a logical or integer match
#'   indicator.
#'
#' @return An updated `il_model` with estimated m parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u() |>
#'   il_estimate_m_from_labels(labelled_pairs)
#' }
il_estimate_m_from_labels <- function(model, labels) {
  validate_il_model(model)
  con <- model$con
  tbl <- model$data$tbl_l
  comparisons <- model$spec$comparisons

  # Get data for labeled pairs
  data <- DBI::dbReadTable(con, tbl)
  id_col <- "unique_id"

  match_pairs <- labels[labels$is_match == TRUE, ]
  if (nrow(match_pairs) == 0L) {
    cli::cli_abort("No matching pairs found in labels.")
  }

  # Build pairs data frame from labels
  pair_rows <- list()
  cols <- model$data$columns
  for (i in seq_len(nrow(match_pairs))) {
    id_l <- match_pairs$unique_id_l[i]
    id_r <- match_pairs$unique_id_r[i]
    row_l <- data[data[[id_col]] == id_l, , drop = FALSE]
    row_r <- data[data[[id_col]] == id_r, , drop = FALSE]
    if (nrow(row_l) > 0L && nrow(row_r) > 0L) {
      pair <- as.data.frame(c(
        stats::setNames(as.list(row_l[1, ]), paste0("l_", names(row_l))),
        stats::setNames(as.list(row_r[1, ]), paste0("r_", names(row_r)))
      ))
      pair_rows <- c(pair_rows, list(pair))
    }
  }

  pairs <- do.call(rbind, pair_rows)
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  comp_names <- colnames(gamma_mat)
  m_match <- colMeans(gamma_mat)
  m_nonmatch <- 1 - m_match

  # Merge with existing parameters
  if (!is.null(model$params$comparisons)) {
    params <- model$params$comparisons
    for (j in seq_along(comp_names)) {
      cn <- comp_names[j]
      params$m[params$comparison == cn & params$level == "match"] <- m_match[j]
      params$m[params$comparison == cn & params$level == "non_match"] <- m_nonmatch[j]
    }
    model$params$comparisons <- params
  } else {
    model$params$comparisons <- tibble::tibble(
      comparison = rep(comp_names, each = 2L),
      level = rep(c("match", "non_match"), times = length(comp_names)),
      m = as.numeric(rbind(m_match, m_nonmatch)),
      u = NA_real_
    )
  }

  model$trained <- TRUE
  model
}
