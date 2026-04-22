# Shared scoring helpers used by predict(), il_find_matches(), and il_waterfall().

#' Safely extract the prior from a model, guarding NULL and NA
#' @param model An il_model object.
#' @param default Fallback value when prior is NULL or NA.
#' @return Numeric scalar.
#' @noRd
safe_prior <- function(model, default = 0.0001) {
  p <- model$params$prior
  if (is.null(p) || is.na(p)) default else p
}

#' Clamp probabilities away from 0 and 1
#' @noRd
clamp_probability <- function(prob, eps = 1e-6) {
  pmin(pmax(prob, eps), 1 - eps)
}

#' Convert a probability to Bayes-factor odds
#' @noRd
prob_to_bayes_factor <- function(prob) {
  prob <- clamp_probability(prob)
  prob / (1 - prob)
}

#' Convert Bayes-factor odds to a probability
#' @noRd
bayes_factor_to_probability <- function(bf) {
  bf <- pmax(bf, 1e-10)
  clamp_probability(bf / (1 + bf))
}

#' Adjust the global prior for exact agreements implied by blocking
#' @noRd
adjust_prior_for_blocking <- function(prior, deactivated,
                                      m_list, u_list, levels_per_comp) {
  if (!any(deactivated)) {
    return(clamp_probability(prior))
  }

  prior_bf <- prob_to_bayes_factor(prior)
  for (j in which(deactivated)) {
    nl <- levels_per_comp[j]
    level_bf <- max(m_list[[j]][nl], 1e-10) / max(u_list[[j]][nl], 1e-10)
    prior_bf <- prior_bf * level_bf
  }

  bayes_factor_to_probability(prior_bf)
}

#' Reverse a blocking adjustment back to the global prior
#' @noRd
reverse_blocking_adjusted_prior <- function(prior, deactivated,
                                            m_list, u_list, levels_per_comp) {
  if (!any(deactivated)) {
    return(clamp_probability(prior))
  }

  prior_bf <- prob_to_bayes_factor(prior)
  for (j in which(deactivated)) {
    nl <- levels_per_comp[j]
    level_bf <- max(m_list[[j]][nl], 1e-10) / max(u_list[[j]][nl], 1e-10)
    prior_bf <- prior_bf / level_bf
  }

  bayes_factor_to_probability(prior_bf)
}

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
    gamma_vals <- gamma_mat[, j]
    observed <- gamma_vals >= 0L
    if (any(observed)) {
      total_weight[observed] <- total_weight[observed] +
        level_weights[gamma_vals[observed] + 1L]
    }
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
    if (gamma[j] >= 0L) {
      contrib[j] <- level_weights[gamma[j] + 1L]
    }
  }
  if (!is.null(tf_adjs)) {
    contrib <- contrib + tf_adjs
  }
  contrib
}
