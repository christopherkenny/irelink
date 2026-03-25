#' Estimate Non-Match (u) Parameters
#'
#' Estimates the u probabilities (the probability of observing each
#' comparison level given that the records do **not** match) by randomly
#' sampling record pairs. Most random pairs are non-matches, so the
#' observed level frequencies approximate the u distribution.
#'
#' @param model An `il_model` object (piped in).
#' @param max_pairs Maximum number of random pairs to sample. Defaults to
#'   `1e6`.
#'
#' @return An updated `il_model` with estimated u parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u(max_pairs = 1e6)
#' }
il_estimate_u <- function(model, max_pairs = 1e6) {
  validate_il_model(model)
  pairs <- get_all_pairs(model, max_pairs = max_pairs)
  comparisons <- model$spec$comparisons

  if (nrow(pairs) == 0L) {
    cli::cli_abort("No pairs available for u estimation.")
  }

  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  # u = fraction of random pairs that agree at each level
  n_pairs <- nrow(pairs)
  u_match <- colMeans(gamma_mat)
  u_nonmatch <- 1 - u_match

  comp_names <- colnames(gamma_mat)
  params_tbl <- tibble::tibble(
    comparison = rep(comp_names, each = 2L),
    level = rep(c("match", "non_match"), times = length(comp_names)),
    u = as.numeric(rbind(u_match, u_nonmatch))
  )

  if (is.null(model$params$comparisons)) {
    params_tbl$m <- NA_real_
  } else {
    params_tbl <- merge(
      params_tbl[, c("comparison", "level", "u")],
      model$params$comparisons[, c("comparison", "level", "m")],
      by = c("comparison", "level"), all.x = TRUE
    )
    params_tbl <- tibble::as_tibble(params_tbl)
  }

  model$params$comparisons <- params_tbl
  model
}
