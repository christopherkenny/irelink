#' Score Record Pairs from a Trained Model
#'
#' Generates and scores all candidate record pairs that pass the blocking
#' rules, returning those above the match-probability threshold. This is
#' an S3 method for [stats::predict()] — the same generic used for `lm`,
#' `glm`, and tidymodels objects.
#'
#' @param object A trained `il_model` object.
#' @param threshold A numeric value between 0 and 1. Only pairs with a
#'   match probability at or above this threshold are returned. Defaults
#'   to `0.85`.
#' @param type One of `"pairs"` (default) to return scored pairs, or
#'   `"weights"` to return match weights on a log-2 Bayes-factor scale.
#' @param ... Additional arguments passed to the generic.
#'
#' @return An `il_compared` tibble with one row per candidate pair,
#'   including columns for record IDs, match weight, match probability,
#'   and per-comparison gamma values.
#' @export
#'
#' @examples
#' \dontrun{
#' pairs <- predict(model, threshold = 0.85)
#'
#' # Filter to high-confidence matches
#' pairs |> dplyr::filter(match_prob > 0.99)
#'
#' # Histogram of match weights
#' pairs |>
#'   ggplot2::ggplot(ggplot2::aes(x = match_weight)) +
#'   ggplot2::geom_histogram(binwidth = 1, fill = "steelblue")
#' }
predict.il_model <- function(object, threshold = 0.85,
                             type = c("pairs", "weights"), ...) {
  type <- match.arg(type)
  validate_il_model(object)

  if (!object$trained) {
    cli::cli_abort("Model must be trained before prediction. Use {.fn il_estimate_em} first.")
  }

  comparisons <- object$spec$comparisons
  params <- object$params$comparisons
  prior <- object$params$prior %||% 0.05
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))

  # Collect blocked pairs from all blocking rules
  blocking_rules <- object$spec$blocking_rules
  all_pairs <- list()
  for (br in blocking_rules) {
    bp <- get_blocked_pairs(object, br)
    if (nrow(bp) > 0L) all_pairs <- c(all_pairs, list(bp))
  }

  if (length(all_pairs) == 0L) {
    empty <- tibble::tibble(
      unique_id_l = integer(0), unique_id_r = integer(0),
      match_weight = numeric(0), match_probability = numeric(0)
    )
    return(new_il_compared(empty, model = object))
  }

  pairs <- do.call(rbind, all_pairs)
  pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = "||")
  pairs <- pairs[!duplicated(pair_key), , drop = FALSE]

  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  n_comp <- length(comparisons)

  mu <- extract_mu_vectors(params, comp_names)
  match_weight <- score_gamma_matrix(gamma_mat, mu)
  match_probability <- weight_to_probability(match_weight, prior)

  result <- tibble::tibble(
    unique_id_l = pairs$l_unique_id,
    unique_id_r = pairs$r_unique_id,
    match_weight = match_weight,
    match_probability = match_probability
  )
  for (j in seq_len(n_comp)) {
    result[[paste0("gamma_", comp_names[j])]] <- gamma_mat[, j]
  }

  result <- result[result$match_probability >= threshold, , drop = FALSE]
  result <- tibble::as_tibble(result)
  new_il_compared(result, model = object)
}
