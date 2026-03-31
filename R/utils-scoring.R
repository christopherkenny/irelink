# Shared scoring helpers used by predict(), il_find_matches(), and il_waterfall().

#' Extract per-level m/u probability lists from a model's parameter tibble
#'
#' For each comparison, returns vectors of m and u probabilities indexed
#' by gamma level (0, 1, ..., K). Compatible with both the new
#' `gamma_level` format and the legacy `level` (match/non_match) format.
#'
#' @param params A tibble with columns `comparison`, `gamma_level`, `m`, `u`
#'   (or legacy `comparison`, `level`, `m`, `u`).
#' @param comp_names Character vector of comparison names, in order.
#' @return A named list with `m_levels` and `u_levels`, each a list of
#'   numeric vectors (one per comparison), indexed from gamma_level 0.
#' @noRd
extract_mu_vectors <- function(params, comp_names) {
  # Detect legacy format and convert
  if ('level' %in% names(params) && !'gamma_level' %in% names(params)) {
    params <- migrate_params_to_gamma_level(params)
  }

  n <- length(comp_names)
  m_levels <- vector('list', n)
  u_levels <- vector('list', n)
  names(m_levels) <- comp_names
  names(u_levels) <- comp_names

  for (j in seq_len(n)) {
    cn <- comp_names[j]
    rows <- params[params$comparison == cn, ]
    rows <- rows[order(rows$gamma_level), ]
    m_levels[[j]] <- pmax(rows$m, 1e-10)
    u_levels[[j]] <- pmax(rows$u, 1e-10)
  }

  list(m_levels = m_levels, u_levels = u_levels)
}

#' Migrate legacy match/non_match params to gamma_level format
#' @param params Tibble with `level` column (match/non_match).
#' @return Tibble with `gamma_level` integer column.
#' @noRd
migrate_params_to_gamma_level <- function(params) {
  params$gamma_level <- ifelse(params$level == 'match', 1L, 0L)
  params$level <- NULL
  params
}

#' Compute match weights from a gamma matrix and per-level m/u
#'
#' For each pair (row) and comparison (column), looks up the weight
#' log2(m / u) for the observed gamma level.
#'
#' @param gamma_mat An integer matrix (n_pairs x n_comparisons).
#' @param mu A list from `extract_mu_vectors()`.
#' @return A numeric vector of match weights (length = nrow(gamma_mat)).
#' @noRd
score_gamma_matrix <- function(gamma_mat, mu) {
  n_pairs <- nrow(gamma_mat)
  n_comp <- ncol(gamma_mat)
  comp_names <- colnames(gamma_mat)

  total_weight <- numeric(n_pairs)
  for (j in seq_len(n_comp)) {
    cn <- comp_names[j]
    m_vec <- mu$m_levels[[cn]]
    u_vec <- mu$u_levels[[cn]]
    level_weights <- log2(m_vec / u_vec)
    # gamma_mat[, j] has values 0..K; R is 1-indexed so add 1
    total_weight <- total_weight + level_weights[gamma_mat[, j] + 1L]
  }
  total_weight
}

#' Convert match weights to match probabilities via logistic transform
#'
#' @param match_weight Numeric vector of match weights (log2 Bayes factors).
#' @param prior Scalar prior match probability.
#' @return Numeric vector of match probabilities in \[0, 1\].
#' @noRd
weight_to_probability <- function(match_weight, prior) {
  log_odds <- log(prior / (1 - prior)) + match_weight * log(2)
  1 / (1 + exp(-log_odds))
}

#' Compute per-comparison contribution for a single gamma vector
#'
#' Used by [il_waterfall()] to decompose a match weight into parts.
#'
#' @param gamma Integer vector (one per comparison) for a single pair.
#' @param mu A list from `extract_mu_vectors()`.
#' @param comp_names Character vector of comparison names.
#' @param tf_adjs Optional numeric vector of per-comparison TF adjustments
#'   (same length as `gamma`). Added to the base contribution for comparisons
#'   with term-frequency weighting.
#' @return Numeric vector of contributions (one per comparison).
#' @noRd
per_comparison_contribution <- function(gamma, mu, comp_names = NULL,
                                        tf_adjs = NULL) {
  n <- length(gamma)
  if (is.null(comp_names)) comp_names <- names(mu$m_levels)
  contrib <- numeric(n)
  for (j in seq_len(n)) {
    cn <- comp_names[j]
    m_vec <- mu$m_levels[[cn]]
    u_vec <- mu$u_levels[[cn]]
    level_weights <- log2(m_vec / u_vec)
    contrib[j] <- level_weights[gamma[j] + 1L]
  }
  if (!is.null(tf_adjs)) {
    contrib <- contrib + tf_adjs
  }
  contrib
}
