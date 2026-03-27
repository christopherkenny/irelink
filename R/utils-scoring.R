# Shared scoring helpers used by predict(), il_find_matches(), and il_waterfall().

#' Extract m and u probability vectors from a model's parameter tibble
#'
#' @param params A tibble with columns `comparison`, `level`, `m`, and `u`.
#' @param comp_names Character vector of comparison names, in order.
#' @return A named list with `m_match`, `m_nonmatch`, `u_match`, `u_nonmatch`
#'   (each a numeric vector aligned to `comp_names`).
#' @noRd
extract_mu_vectors <- function(params, comp_names) {
  n <- length(comp_names)
  m_match <- m_nonmatch <- u_match <- u_nonmatch <- numeric(n)
  for (j in seq_len(n)) {
    cn <- comp_names[j]
    m_match[j] <- params$m[params$comparison == cn & params$level == 'match']
    m_nonmatch[j] <- params$m[params$comparison == cn & params$level == 'non_match']
    u_match[j] <- params$u[params$comparison == cn & params$level == 'match']
    u_nonmatch[j] <- params$u[params$comparison == cn & params$level == 'non_match']
  }
  list(
    m_match = m_match, m_nonmatch = m_nonmatch,
    u_match = u_match, u_nonmatch = u_nonmatch
  )
}

#' Compute match weights from a gamma matrix and m/u vectors
#'
#' Each row of the gamma matrix is a record pair; each column is a comparison.
#' Returns the log2 Bayes factor (match weight) summed across comparisons.
#' Uses a single matrix-vector multiply for speed.
#'
#' @param gamma_mat An integer matrix (n_pairs x n_comparisons).
#' @param mu A list from `extract_mu_vectors()`.
#' @return A numeric vector of match weights (length = nrow(gamma_mat)).
#' @noRd
score_gamma_matrix <- function(gamma_mat, mu) {
  w1 <- log2(pmax(mu$m_match, 1e-10) / pmax(mu$u_match, 1e-10))
  w0 <- log2(pmax(mu$m_nonmatch, 1e-10) / pmax(mu$u_nonmatch, 1e-10))
  as.numeric(gamma_mat %*% (w1 - w0)) + sum(w0)
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
#' @return Numeric vector of contributions (one per comparison).
#' @noRd
per_comparison_contribution <- function(gamma, mu) {
  w1 <- log2(pmax(mu$m_match, 1e-10) / pmax(mu$u_match, 1e-10))
  w0 <- log2(pmax(mu$m_nonmatch, 1e-10) / pmax(mu$u_nonmatch, 1e-10))
  ifelse(gamma == 1L, w1, w0)
}
