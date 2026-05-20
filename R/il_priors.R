#' Add a Prevalence Prior
#'
#' Sets a target for the global match prevalence. With `strength = NULL`, the
#' target is used only as the model's starting prior. With a finite strength,
#' EM also uses the target as Beta pseudo-counts.
#'
#' @param model An `il_model` object.
#' @param probability Target match probability, strictly between 0 and 1.
#' @param strength Optional non-negative effective sample size.
#'
#' @return The model with prior metadata stored in `model$params$priors`.
#' @export
il_prior_prevalence <- function(model, probability, strength = NULL) {
  validate_il_model(model)
  probability <- validate_probability_scalar(
    probability,
    'probability',
    allow_boundary = FALSE
  )
  strength <- validate_strength(strength)

  model$params$prior <- probability
  row <- tibble::tibble(
    family = 'prevalence',
    comparison = NA_character_,
    gamma_level = NA_integer_,
    probability = probability,
    strength = strength %||% NA_real_
  )
  model$params$priors <- upsert_prior_rows(model$params$priors, row)
  model
}

#' Add a Matched-Class Comparison Prior
#'
#' Adds a Dirichlet regularizing prior for one comparison's matched-class `m`
#' probabilities. Use `exact` for the strongest agreement level, or `levels`
#' for a complete named gamma-level distribution.
#'
#' @param model An `il_model` object.
#' @param col Comparison column, supplied as a bare name or string.
#' @param exact Probability for the strongest gamma level.
#' @param levels Complete named probability vector, with names such as `"0"`,
#'   `"1"`, and `"2"`.
#' @param strength Non-negative effective sample size.
#' @param remainder How to distribute non-exact probability. Currently
#'   `"current"` uses trained/current `m` probabilities when available and
#'   otherwise falls back to uniform.
#'
#' @return The model with prior metadata stored in `model$params$priors`.
#' @export
il_prior_m <- function(
  model,
  col,
  exact = NULL,
  levels = NULL,
  strength,
  remainder = c('current')
) {
  validate_il_model(model)
  col <- as.character(rlang::ensym(col))
  strength <- validate_strength(strength, allow_null = FALSE)
  remainder <- match.arg(remainder)

  dist <- prior_distribution(
    model,
    col,
    exact = exact,
    levels = levels,
    remainder = remainder,
    full_for_exact = TRUE
  )
  row <- tibble::tibble(
    family = 'm',
    comparison = col,
    gamma_level = as.integer(names(dist)),
    probability = as.numeric(dist),
    strength = strength
  )
  if (is.null(model$params[['prior']])) {
    model$params$prior <- safe_prior(model)
  }
  model$params$priors <- upsert_prior_rows(model$params$priors, row)
  model
}

#' Add a Fixed Matched-Class Constraint
#'
#' Fixes one comparison's matched-class `m` probabilities during EM. This is a
#' hard constraint, stored separately from regularizing priors.
#'
#' @param model An `il_model` object.
#' @param col Comparison column, supplied as a bare name or string.
#' @param exact Probability for the strongest gamma level.
#' @param levels Complete named probability vector, with names such as `"0"`,
#'   `"1"`, and `"2"`.
#'
#' @return The model with constraint metadata in `model$params$constraints`.
#' @export
il_constrain_m <- function(model, col, exact = NULL, levels = NULL) {
  validate_il_model(model)
  col <- as.character(rlang::ensym(col))

  dist <- prior_distribution(
    model,
    col,
    exact = exact,
    levels = levels,
    remainder = 'current',
    full_for_exact = FALSE
  )
  row <- tibble::tibble(
    family = 'm',
    comparison = col,
    gamma_level = as.integer(names(dist)),
    probability = as.numeric(dist)
  )
  if (is.null(model$params[['prior']])) {
    model$params$prior <- safe_prior(model)
  }
  model$params$constraints <- upsert_constraint_rows(
    model$params$constraints,
    row
  )
  model
}

#' Inspect Model Priors
#'
#' @param model An `il_model` object.
#' @return A tibble of stored prior metadata.
#' @export
il_priors <- function(model) {
  validate_il_model(model)
  model$params$priors %||% empty_priors_tbl()
}

#' Inspect Model Constraints
#'
#' @param model An `il_model` object.
#' @return A tibble of stored fixed-constraint metadata.
#' @export
il_constraints <- function(model) {
  validate_il_model(model)
  model$params$constraints %||% empty_constraints_tbl()
}

validate_probability_scalar <- function(
  x,
  arg = 'probability',
  allow_boundary = TRUE
) {
  if (
    !is.numeric(x) ||
      length(x) != 1L ||
      !is.finite(x) ||
      is.na(x) ||
      x < 0 ||
      x > 1
  ) {
    cli::cli_abort('{.arg {arg}} must be a finite probability between 0 and 1.')
  }
  if (!allow_boundary && (x <= 0 || x >= 1)) {
    cli::cli_abort('{.arg {arg}} must be strictly between 0 and 1.')
  }
  as.numeric(x)
}

validate_strength <- function(x, allow_null = TRUE) {
  if (is.null(x) && allow_null) {
    return(NULL)
  }
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || is.na(x) || x < 0) {
    cli::cli_abort('{.arg strength} must be a finite non-negative number.')
  }
  as.numeric(x)
}

prior_distribution <- function(
  model,
  col,
  exact = NULL,
  levels = NULL,
  remainder = 'current',
  full_for_exact = TRUE
) {
  if (!xor(is.null(exact), is.null(levels))) {
    cli::cli_abort('Supply exactly one of {.arg exact} or {.arg levels}.')
  }
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  idx <- match(col, comp_names)
  if (is.na(idx)) {
    cli::cli_abort(
      'Column {.field {col}} is not present as an {.fn il_compare} layer.'
    )
  }

  n_levels <- n_gamma_levels(comparisons[[idx]]$method)
  level_names <- as.character(seq(0L, n_levels - 1L))

  if (!is.null(levels)) {
    return(validate_level_distribution(levels, level_names))
  }

  exact <- validate_probability_scalar(exact, 'exact')
  highest <- as.character(n_levels - 1L)
  if (!full_for_exact) {
    out <- stats::setNames(exact, highest)
    return(out)
  }

  out <- numeric(n_levels)
  names(out) <- level_names
  out[highest] <- exact
  other <- setdiff(level_names, highest)
  out[other] <- (1 - exact) * remainder_weights(model, col, other)
  out
}

validate_level_distribution <- function(levels, expected_names) {
  if (
    !is.numeric(levels) ||
      is.null(names(levels)) ||
      anyNA(levels) ||
      !all(is.finite(levels)) ||
      any(levels < 0)
  ) {
    cli::cli_abort(
      '{.arg levels} must be a named numeric vector of finite non-negative probabilities.'
    )
  }
  if (any(names(levels) == '') || anyDuplicated(names(levels))) {
    cli::cli_abort(
      '{.arg levels} must have unique non-empty gamma-level names.'
    )
  }
  if (!setequal(names(levels), expected_names)) {
    cli::cli_abort(
      '{.arg levels} must name exactly gamma levels {.val {expected_names}}.'
    )
  }
  total <- sum(levels)
  if (!isTRUE(all.equal(total, 1, tolerance = 1e-8))) {
    cli::cli_abort('{.arg levels} probabilities must sum to 1.')
  }
  levels[expected_names]
}

remainder_weights <- function(model, col, level_names) {
  params <- model$params$comparisons
  if (!is.null(params)) {
    if ('level' %in% names(params) && !'gamma_level' %in% names(params)) {
      params <- migrate_params_to_gamma_level(params)
    }
    rows <- params[params$comparison == col, , drop = FALSE]
    rows <- rows[
      match(as.integer(level_names), rows$gamma_level),
      ,
      drop = FALSE
    ]
    if (
      nrow(rows) == length(level_names) &&
        all(is.finite(rows$m)) &&
        sum(rows$m, na.rm = TRUE) > 0
    ) {
      w <- rows$m / sum(rows$m)
      names(w) <- level_names
      return(w)
    }
  }
  stats::setNames(
    rep(1 / length(level_names), length(level_names)),
    level_names
  )
}

empty_priors_tbl <- function() {
  tibble::tibble(
    family = character(),
    comparison = character(),
    gamma_level = integer(),
    probability = numeric(),
    strength = numeric()
  )
}

empty_constraints_tbl <- function() {
  tibble::tibble(
    family = character(),
    comparison = character(),
    gamma_level = integer(),
    probability = numeric()
  )
}

upsert_prior_rows <- function(existing, rows) {
  existing <- existing %||% empty_priors_tbl()
  keep <- rep(TRUE, nrow(existing))
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    comparison_same <- !is.na(existing$comparison) &
      existing$comparison == r$comparison
    if (is.na(r$comparison)) {
      comparison_same <- is.na(existing$comparison)
    }
    gamma_same <- !is.na(existing$gamma_level) &
      existing$gamma_level == r$gamma_level
    if (is.na(r$gamma_level)) {
      gamma_same <- is.na(existing$gamma_level)
    }
    same <- existing$family == r$family & comparison_same & gamma_same
    keep <- keep & !same
  }
  tibble::as_tibble(rbind(existing[keep, , drop = FALSE], rows))
}

upsert_constraint_rows <- function(existing, rows) {
  existing <- existing %||% empty_constraints_tbl()
  keep <- !(existing$family == 'm' & existing$comparison %in% rows$comparison)
  tibble::as_tibble(rbind(existing[keep, , drop = FALSE], rows))
}

em_prior_metadata <- function(
  model,
  deactivated,
  comp_names,
  levels_per_comp,
  m_list,
  u_list
) {
  priors <- model$params$priors
  constraints <- model$params$constraints
  validate_em_prior_targets(priors, constraints, deactivated, comp_names)

  prevalence <- NULL
  if (!is.null(priors) && nrow(priors) > 0L) {
    prevalence_rows <- priors[
      priors$family == 'prevalence' &
        is.finite(priors$strength) &
        priors$strength > 0,
      ,
      drop = FALSE
    ]
    if (nrow(prevalence_rows) > 0L) {
      row <- prevalence_rows[nrow(prevalence_rows), ]
      target <- adjust_prior_for_blocking(
        row$probability,
        deactivated,
        m_list,
        u_list,
        levels_per_comp
      )
      prevalence <- list(
        probability = target,
        strength = row$strength
      )
    }
  }

  m_priors <- split_m_metadata(priors, comp_names)
  m_constraints <- split_m_metadata(constraints, comp_names)
  list(
    prevalence = prevalence,
    m_priors = m_priors,
    m_constraints = m_constraints
  )
}

validate_em_prior_targets <- function(
  priors,
  constraints,
  deactivated,
  comp_names
) {
  bad <- character(0)
  for (tbl in list(priors, constraints)) {
    if (is.null(tbl) || nrow(tbl) == 0L) {
      next
    }
    field_rows <- tbl[tbl$family == 'm', , drop = FALSE]
    bad <- c(bad, intersect(field_rows$comparison, comp_names[deactivated]))
  }
  bad <- unique(bad)
  if (length(bad) > 0L) {
    cli::cli_abort(
      'Prior or constraint target{?s} deactivated by the EM blocking rule: {.field {bad}}.'
    )
  }
}

split_m_metadata <- function(tbl, comp_names) {
  out <- vector('list', length(comp_names))
  names(out) <- comp_names
  if (is.null(tbl) || nrow(tbl) == 0L) {
    return(out)
  }
  tbl <- tbl[tbl$family == 'm', , drop = FALSE]
  for (cn in intersect(comp_names, unique(tbl$comparison))) {
    rows <- tbl[tbl$comparison == cn, , drop = FALSE]
    probs <- rows$probability
    names(probs) <- as.character(rows$gamma_level)
    out[[cn]] <- probs
  }
  out
}

model_prior_strength <- function(priors, comparison) {
  if (is.null(priors) || nrow(priors) == 0L) {
    return(0)
  }
  rows <- priors[
    priors$family == 'm' & priors$comparison == comparison,
    ,
    drop = FALSE
  ]
  if (nrow(rows) == 0L) {
    return(0)
  }
  unique_strength <- unique(rows$strength)
  unique_strength <- unique_strength[is.finite(unique_strength)]
  if (length(unique_strength) == 0L) {
    return(0)
  }
  unique_strength[[length(unique_strength)]]
}

apply_m_constraint <- function(raw, constraint) {
  if (is.null(constraint)) {
    return(raw)
  }
  fixed_idx <- as.integer(names(constraint)) + 1L
  fixed_prob <- as.numeric(constraint)
  if (sum(fixed_prob) > 1 + 1e-8) {
    cli::cli_abort('Fixed m constraints for a comparison must not sum above 1.')
  }
  out <- raw
  out[fixed_idx] <- fixed_prob
  free_idx <- setdiff(seq_along(raw), fixed_idx)
  remaining <- max(0, 1 - sum(fixed_prob))
  if (length(free_idx) > 0L) {
    free_sum <- sum(raw[free_idx])
    if (free_sum > 0) {
      out[free_idx] <- raw[free_idx] / free_sum * remaining
    } else {
      out[free_idx] <- remaining / length(free_idx)
    }
  }
  out / sum(out)
}
