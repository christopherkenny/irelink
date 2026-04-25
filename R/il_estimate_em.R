#' Train Parameters via Expectation-Maximisation
#'
#' Runs the EM algorithm under a blocking rule to learn m and u parameters
#' from unlabelled data. Multiple calls with different blocking rules can
#' be chained to train on complementary subsets of record pairs — each
#' call updates the model cumulatively.
#'
#' @param model An `il_model` object (piped in).
#' @param blocking A blocking rule created by [block_on()].
#' @param convergence A numeric convergence tolerance. The EM loop stops
#'   when the largest change in any updated parameter is below this value.
#'   Defaults to `1e-5`.
#' @param fix_u Logical. If `TRUE` (the default), hold u parameters fixed
#'   during EM — only m is updated. Set to `FALSE` to also estimate u.
#'   Only supported with `estimator_mode = "independent"`.
#' @param fix_m Logical. If `TRUE`, hold m parameters fixed during EM.
#'   Defaults to `FALSE`. At least one of `fix_u` and `fix_m` must be
#'   `FALSE`, otherwise the algorithm cannot learn anything. Only supported
#'   with `estimator_mode = "independent"`.
#' @param max_iterations Maximum number of EM iterations. Defaults to
#'   `100L`. The loop stops early when convergence is reached.
#' @param fix_prior Logical. If `TRUE`, hold the prior (probability that
#'   two random records match) fixed during EM iterations.
#'   Defaults to `FALSE`.
#' @param estimate_without_tf Logical. If `TRUE` (the default), EM runs
#'   on aggregated gamma-pattern counts (fast, but ignores per-pair term
#'   frequency variation). If `FALSE`, EM runs on individual pairs and
#'   incorporates per-pair TF adjustments in the E-step, matching
#'   splink's default behaviour. Only matters when at least one
#'   comparison has `term_frequency = TRUE`. Only supported with
#'   `estimator_mode = "independent"`.
#' @param derive_prior Logical. If `TRUE`, derive the prior from the
#'   trained parameter values after EM completes and store it in the
#'   model. Defaults to `FALSE`. Only supported with
#'   `estimator_mode = "independent"`.
#' @param estimator_mode Estimator to use. `"independent"` keeps the
#'   conditionally independent Fellegi-Sunter EM estimator. `"dependency-aware"`
#'   fits log-linear matched and unmatched comparison-pattern distributions.
#' @param ... Reserved for future options.
#'
#' @return An updated `il_model` with trained m and u parameters.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c(
#'     'John', 'Jon', 'Jane', 'Jane', 'Bob',
#'     'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
#'     'John', 'Jon', 'Jane', 'Janet', 'Bob',
#'     'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
#'   ),
#'   surname = c(
#'     'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Brown', 'White', 'White',
#'     'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Browne', 'White', 'White'
#'   ),
#'   dob = c(
#'     '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
#'     '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
#'     '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
#'     '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
#'     '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
#'   ),
#'   city = c(
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
#'   ),
#'   email = c(
#'     'john@example.com', 'jon@example.com', 'jane@example.com',
#'     'jane@example.com', 'bob@example.com', 'bobby@example.com',
#'     'alice@example.com', 'alicia@example.com', 'tom@example.com',
#'     'thomas@example.com', 'john@example.com', 'jon@example.com',
#'     'jane@example.com', 'janet@example.com', 'bob@example.com',
#'     'robert@example.com', 'alice@example.com', 'alison@example.com',
#'     'tom@example.com', 'tomas@example.com'
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#'
#' model <- il_estimate_em(model, block_on(surname))
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_estimate_em <- function(model, blocking, convergence = 1e-5,
                           fix_u = TRUE, fix_m = FALSE,
                           max_iterations = 100L,
                           fix_prior = FALSE,
                           estimate_without_tf = TRUE,
                           derive_prior = FALSE,
                           estimator_mode = c('independent', 'dependency-aware'),
                           ...) {
  fix_u_supplied <- !missing(fix_u)
  fix_m_supplied <- !missing(fix_m)
  estimate_without_tf_supplied <- !missing(estimate_without_tf)
  estimator_mode <- match.arg(estimator_mode)
  validate_il_model(model)
  if (!is.numeric(max_iterations) || length(max_iterations) != 1L ||
    max_iterations < 1L || max_iterations != as.integer(max_iterations)) {
    cli::cli_abort('{.arg max_iterations} must be a positive integer.')
  }
  max_iterations <- as.integer(max_iterations)
  comparisons <- model$spec$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  n_comp <- length(comp_names)

  # Decide whether to use per-pair TF-inclusive EM
  has_tf <- any(vapply(comparisons, function(c) {
    isTRUE(c$method$term_frequency)
  }, logical(1)))

  if (identical(estimator_mode, 'dependency-aware')) {
    return(il_estimate_em_dependency_aware(
      model = model,
      blocking = blocking,
      convergence = convergence,
      max_iterations = max_iterations,
      fix_prior = fix_prior,
      fix_u_supplied = fix_u_supplied,
      fix_m_supplied = fix_m_supplied,
      estimate_without_tf_supplied = estimate_without_tf_supplied,
      derive_prior = derive_prior,
      has_tf = has_tf
    ))
  }

  if (fix_u && fix_m) {
    cli::cli_abort('At least one of {.arg fix_u} and {.arg fix_m} must be {.code FALSE}.')
  }

  use_pair_level <- !estimate_without_tf && has_tf

  # For pair-level EM, retrieve individual pairs with TF data
  pair_tf_data <- NULL
  if (use_pair_level) {
    pair_result <- get_pairs_with_gammas(model, list(blocking))
    if (nrow(pair_result$gamma_mat) == 0L) {
      cli::cli_abort('No pairs generated by the blocking rule. Choose a less restrictive rule.')
    }
  }

  # Column deactivation: identify comparisons that overlap with the

  # blocking rule's columns and exclude them from estimation (splink's
  # approach — blocking on a column means it must match, so gamma is
  # always the highest level and m/u cannot be estimated from the data).
  br_cols <- blocking$columns
  deactivated <- vapply(comparisons, function(c) {
    any(c$columns %in% br_cols)
  }, logical(1))
  validate_em_prior_targets(
    model$params$priors, model$params$constraints, deactivated, comp_names
  )

  result <- get_pairs_with_gamma_counts(model, list(blocking))

  if (result$n_pairs == 0L) {
    cli::cli_abort('No pairs generated by the blocking rule. Choose a less restrictive rule.')
  }

  n_pairs <- result$n_pairs
  trained_names <- comp_names[!deactivated]
  deact_names <- comp_names[deactivated]
  if (length(trained_names) > 0 && length(deact_names) > 0) {
    cli::cli_inform(
      'EM trained: {.field {trained_names}} | skipped (blocked on): {.field {deact_names}}'
    )
  } else if (length(trained_names) > 0) {
    cli::cli_inform('EM trained: {.field {trained_names}}')
  } else {
    cli::cli_inform('EM: all comparisons overlap with the blocking rule; nothing was trained.')
  }

  # Extract gamma patterns and counts (or per-pair gammas for TF mode)
  if (use_pair_level) {
    pattern_mat <- pair_result$gamma_mat
    pattern_mat[is.na(pattern_mat)] <- 0L
    storage.mode(pattern_mat) <- 'integer'
    colnames(pattern_mat) <- comp_names
    pattern_n <- rep(1, nrow(pattern_mat))
    n_patterns <- nrow(pattern_mat)
    pair_tf_data <- pair_result$tf_data
  } else {
    gamma_cols <- paste0('gamma_', comp_names)
    pattern_mat <- as.matrix(result$counts[, gamma_cols, drop = FALSE])
    pattern_mat[is.na(pattern_mat)] <- 0L
    storage.mode(pattern_mat) <- 'integer'
    colnames(pattern_mat) <- comp_names
    pattern_n <- as.numeric(result$counts$n)
    n_patterns <- nrow(pattern_mat)
  }

  # Determine number of gamma levels per comparison
  levels_per_comp <- vapply(comparisons, function(c) n_gamma_levels(c$method), integer(1))

  # Initialize m and u as per-level vectors (list of numeric vectors)
  m_list <- vector('list', n_comp)
  u_list <- vector('list', n_comp)
  names(m_list) <- comp_names
  names(u_list) <- comp_names

  params <- model$params$comparisons
  if (!is.null(params)) {
    if ('level' %in% names(params) && !'gamma_level' %in% names(params)) {
      params <- migrate_params_to_gamma_level(params)
    }
  }

  for (j in seq_len(n_comp)) {
    cn <- comp_names[j]
    nl <- levels_per_comp[j]

    # Default m: high probability for highest level, low for others
    m_default <- rep(0.1 / max(nl - 1L, 1L), nl)
    m_default[nl] <- 0.9
    u_default <- rep(1 / nl, nl)

    if (!is.null(params)) {
      rows <- params[params$comparison == cn, ]
      rows <- rows[order(rows$gamma_level), ]
      if (nrow(rows) == nl) {
        m_vec <- ifelse(is.na(rows$m), m_default, rows$m)
        u_vec <- ifelse(is.na(rows$u), u_default, rows$u)
      } else {
        m_vec <- m_default
        u_vec <- u_default
      }
    } else {
      m_vec <- m_default
      u_vec <- u_default
    }
    m_list[[j]] <- m_vec
    u_list[[j]] <- u_vec
  }

  global_prior <- safe_prior(model)
  prior <- adjust_prior_for_blocking(
    global_prior, deactivated, m_list, u_list, levels_per_comp
  )
  prior_info <- em_prior_metadata(
    model, deactivated, comp_names, levels_per_comp, m_list, u_list
  )

  max_iter <- max_iterations
  tol <- convergence
  history <- list()

  for (iter in seq_len(max_iter)) {
    # E-step: compute posterior match probability per pattern (not per pair)
    log_match <- rep(log(prior), n_patterns)
    log_nonmatch <- rep(log(1 - prior), n_patterns)

    for (j in seq_len(n_comp)) {
      # Skip deactivated comparisons in E-step — their contribution is
      # already captured by the blocking-adjusted prior (splink removes
      # them from the comparison list entirely).
      if (deactivated[j]) next
      m_vec <- pmax(m_list[[j]], 1e-10)
      u_vec <- pmax(u_list[[j]], 1e-10)
      log_m_vals <- log(m_vec)
      log_u_vals <- log(u_vec)
      gamma_vals <- pattern_mat[, j]
      observed <- gamma_vals >= 0L
      if (any(observed)) {
        idx <- gamma_vals[observed] + 1L
        log_match[observed] <- log_match[observed] + log_m_vals[idx]
        log_nonmatch[observed] <- log_nonmatch[observed] + log_u_vals[idx]
      }
    }

    # Per-pair TF adjustment in E-step (only in pair-level mode)
    if (use_pair_level && !is.null(pair_tf_data)) {
      for (j in seq_len(n_comp)) {
        comp <- comparisons[[j]]
        if (!isTRUE(comp$method$term_frequency)) next
        col <- comp$columns
        tf_w <- comp$tf_adjustment_weight %||% 1.0
        if (tf_w == 0) next

        tf_l <- pair_tf_data[[paste0('tf_', col, '_l')]]
        tf_r <- pair_tf_data[[paste0('tf_', col, '_r')]]
        if (is.null(tf_l) || is.null(tf_r)) next

        tf_max <- pmax(tf_l, tf_r, na.rm = TRUE)
        tf_min <- comp$tf_minimum_u_value %||% 0.0
        if (tf_min > 0) tf_max <- pmax(tf_max, tf_min)

        max_level <- n_gamma_levels(comp$method) - 1L
        u_exact <- pmax(u_list[[j]][max_level + 1L], 1e-10)

        mask <- pattern_mat[, j] == max_level & !is.na(tf_max) & tf_max > 0
        if (any(mask)) {
          log_tf_adj <- tf_w * (log(u_exact) - log(tf_max[mask]))
          log_match[mask] <- log_match[mask] + log_tf_adj
        }
      }
    }

    max_log <- pmax(log_match, log_nonmatch)
    weights <- exp(log_match - max_log) /
      (exp(log_match - max_log) + exp(log_nonmatch - max_log))

    # M-step: update m and/or u per-level (weighted by pattern counts)
    sum_w <- sum(weights * pattern_n)
    sum_nw <- sum((1 - weights) * pattern_n)
    old_m_list <- m_list
    old_u_list <- u_list
    old_prior <- prior

    # Update prior unless fixed
    if (!fix_prior) {
      if (!is.null(prior_info$prevalence)) {
        alpha <- prior_info$prevalence$probability * prior_info$prevalence$strength
        beta <- (1 - prior_info$prevalence$probability) * prior_info$prevalence$strength
        prior <- clamp_probability((sum_w + alpha) / (n_pairs + alpha + beta))
      } else {
        prior <- clamp_probability(sum_w / n_pairs)
      }
    }

    if (!fix_m) {
      for (j in seq_len(n_comp)) {
        if (deactivated[j]) next
        nl <- levels_per_comp[j]
        raw <- numeric(nl)
        prior_alpha <- rep(0, nl)
        m_prior <- prior_info$m_priors[[comp_names[j]]]
        if (!is.null(m_prior)) {
          prior_alpha[as.integer(names(m_prior)) + 1L] <-
            as.numeric(m_prior) * model_prior_strength(
              model$params$priors, comp_names[j]
            )
        }
        for (k in seq(0L, nl - 1L)) {
          mask <- pattern_mat[, j] == k
          raw[k + 1L] <- (
            sum(weights[mask] * pattern_n[mask]) +
              0.5 / nl + prior_alpha[k + 1L]
          ) / (sum_w + 0.5 + sum(prior_alpha))
        }
        raw <- pmax(raw, 0.001)
        raw <- raw / sum(raw)
        raw <- apply_m_constraint(raw, prior_info$m_constraints[[comp_names[j]]])
        m_list[[j]] <- raw
      }
    } else {
      for (j in seq_len(n_comp)) {
        if (deactivated[j]) next
        m_list[[j]] <- apply_m_constraint(
          m_list[[j]], prior_info$m_constraints[[comp_names[j]]]
        )
      }
    }

    if (!fix_u) {
      for (j in seq_len(n_comp)) {
        if (deactivated[j]) next
        nl <- levels_per_comp[j]
        raw <- numeric(nl)
        for (k in seq(0L, nl - 1L)) {
          mask <- pattern_mat[, j] == k
          raw[k + 1L] <- (sum((1 - weights[mask]) * pattern_n[mask]) + 0.5 / nl) / (sum_nw + 0.5)
        }
        raw <- pmax(raw, 0.001)
        raw <- raw / sum(raw)
        u_list[[j]] <- raw
      }
    }

    history[[iter]] <- tibble::tibble(
      session = length(model$params$history) + 1L,
      iteration = iter,
      comparison = rep(comp_names, times = levels_per_comp),
      gamma_level = unlist(lapply(levels_per_comp, function(nl) seq(0L, nl - 1L))),
      value = unlist(m_list)
    )

    changes <- numeric(0)
    if (!fix_m) {
      changes <- c(changes, vapply(seq_len(n_comp), function(j) {
        max(abs(m_list[[j]] - old_m_list[[j]]))
      }, numeric(1)))
    }
    if (!fix_u) {
      changes <- c(changes, vapply(seq_len(n_comp), function(j) {
        max(abs(u_list[[j]] - old_u_list[[j]]))
      }, numeric(1)))
    }
    if (!fix_prior) {
      changes <- c(changes, abs(prior - old_prior))
    }
    max_change <- max(changes)
    if (max_change < tol) break
  }

  # Store updated parameters
  rows <- list()
  for (j in seq_len(n_comp)) {
    cn <- comp_names[j]
    nl <- levels_per_comp[j]
    for (k in seq(0L, nl - 1L)) {
      rows <- c(rows, list(data.frame(
        comparison = cn,
        gamma_level = k,
        m = m_list[[j]][k + 1L],
        u = u_list[[j]][k + 1L],
        stringsAsFactors = FALSE
      )))
    }
  }
  model$params$comparisons <- tibble::as_tibble(do.call(rbind, rows))

  # Store the global prior, not the blocking-enriched training prior.
  if (!fix_prior) {
    model$params$prior <- reverse_blocking_adjusted_prior(
      prior, deactivated, m_list, u_list, levels_per_comp
    )
  }

  # Derive prior from trained parameter values
  if (derive_prior) {
    derived_prior <- derive_prior_from_params(
      m_list, u_list, pattern_mat, pattern_n
    )
    model$params$prior <- reverse_blocking_adjusted_prior(
      derived_prior, deactivated, m_list, u_list, levels_per_comp
    )
  }

  model$params$history <- c(model$params$history, history)
  model$trained <- TRUE
  model
}

#' Derive the prior from trained EM parameters
#'
#' After EM converges, the proportion of expected matches gives an
#' estimate of the prior probability that two random records match.
#'
#' @param m_list List of m probability vectors per comparison.
#' @param u_list List of u probability vectors per comparison.
#' @param pattern_mat Integer matrix of unique gamma patterns.
#' @param pattern_n Numeric vector of counts per pattern.
#' @return Numeric scalar — the derived prior.
#' @noRd
derive_prior_from_params <- function(m_list, u_list, pattern_mat, pattern_n) {
  n_comp <- ncol(pattern_mat)
  n_patterns <- nrow(pattern_mat)
  log_bf <- numeric(n_patterns)
  for (j in seq_len(n_comp)) {
    m_vec <- pmax(m_list[[j]], 1e-10)
    u_vec <- pmax(u_list[[j]], 1e-10)
    gamma_vals <- pattern_mat[, j]
    observed <- gamma_vals >= 0L
    if (any(observed)) {
      idx <- gamma_vals[observed] + 1L
      log_bf[observed] <- log_bf[observed] + log(m_vec[idx]) - log(u_vec[idx])
    }
  }
  bf <- exp(log_bf)
  # Weighted average posterior match probability with a flat 0.5 prior
  sum((bf / (1 + bf)) * pattern_n) / sum(pattern_n)
}
