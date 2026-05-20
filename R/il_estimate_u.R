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
#' @param min_count_per_level Optional integer. When set, chunked estimation
#'   stops once every comparison level has been observed at least this many
#'   times, or once `max_pairs` has been sampled.
#' @param chunk_size Optional integer number of pairs to score per chunk. When
#'   set, u estimation accumulates gamma counts across chunks instead of using
#'   one aggregate query.
#' @param profile_sql Logical. If `TRUE`, store lightweight SQL timing metadata
#'   in `model$params$sql_profile`.
#'
#' @return An updated `il_model` with estimated u parameters.
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
#'
#' model <- il_estimate_u(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_estimate_u <- function(
  model,
  max_pairs = 1e6,
  min_count_per_level = NULL,
  chunk_size = NULL,
  profile_sql = FALSE
) {
  validate_il_model(model)
  profile <- il_new_sql_profile(profile_sql)
  max_pairs <- validate_positive_count(max_pairs, 'max_pairs')
  if (!is.null(min_count_per_level)) {
    min_count_per_level <- validate_positive_count(
      min_count_per_level,
      'min_count_per_level'
    )
  }
  if (!is.null(chunk_size)) {
    chunk_size <- validate_positive_count(chunk_size, 'chunk_size')
  }
  use_chunked <- !is.null(min_count_per_level) || !is.null(chunk_size)
  if (use_chunked) {
    if (is.null(chunk_size)) {
      chunk_size <- min(max_pairs, 100000L)
    }
    result <- get_random_pair_gamma_counts_chunked(
      model,
      max_pairs = max_pairs,
      chunk_size = chunk_size,
      min_count_per_level = min_count_per_level,
      profile = profile
    )
  } else {
    result <- get_random_pairs_with_gammas(
      model,
      max_pairs = max_pairs,
      profile = profile
    )
    result$stopped_early <- FALSE
    result$n_chunks <- 1L
  }

  if (result$n_pairs == 0L) {
    cli::cli_abort('No pairs available for u estimation.')
  }

  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  counts <- result$counts
  # SQL NULLs come through as NA; treat as else/null level (0)
  for (gcol in paste0('gamma_', comp_names)) {
    if (gcol %in% names(counts)) {
      counts[[gcol]][is.na(counts[[gcol]])] <- 0L
    }
  }
  n_pairs <- result$n_pairs

  rows <- list()
  for (j in seq_along(comp_names)) {
    cn <- comp_names[j]
    gcol <- paste0('gamma_', cn)
    n_levels <- n_gamma_levels(comparisons[[j]]$method)
    u_vals <- numeric(n_levels)
    for (k in seq(0L, n_levels - 1L)) {
      count_k <- sum(counts$n[counts[[gcol]] == k], na.rm = TRUE)
      u_k <- count_k / n_pairs
      u_vals[k + 1L] <- max(u_k, 1e-6)
    }
    u_vals <- u_vals / sum(u_vals)
    for (k in seq(0L, n_levels - 1L)) {
      rows <- c(
        rows,
        list(data.frame(
          comparison = cn,
          gamma_level = k,
          u = u_vals[k + 1L],
          stringsAsFactors = FALSE
        ))
      )
    }
  }
  params_tbl <- tibble::as_tibble(do.call(rbind, rows))

  if (is.null(model$params$comparisons)) {
    params_tbl$m <- NA_real_
  } else {
    old_params <- model$params$comparisons
    params_tbl <- merge(
      params_tbl[, c('comparison', 'gamma_level', 'u')],
      old_params[, c('comparison', 'gamma_level', 'm')],
      by = c('comparison', 'gamma_level'),
      all.x = TRUE
    )
    params_tbl <- tibble::as_tibble(params_tbl)
  }

  model$params$comparisons <- params_tbl
  sampled_chunk_size <- NULL
  if (use_chunked) {
    sampled_chunk_size <- chunk_size
  }
  model$params$u_estimation <- list(
    n_pairs_sampled = n_pairs,
    stopped_early = isTRUE(result$stopped_early),
    min_count_per_level = min_count_per_level,
    chunk_size = sampled_chunk_size,
    max_pairs = max_pairs,
    n_chunks = result$n_chunks %||% NA_integer_
  )
  if (isTRUE(profile_sql)) {
    model$params$sql_profile <- il_sql_profile_entries(profile)
  }
  model
}

#' Validate count-like scalar arguments
#' @noRd
validate_positive_count <- function(x, arg) {
  if (
    !is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x <= 0
  ) {
    cli::cli_abort('{.arg {arg}} must be a positive finite number.')
  }
  as.integer(x)
}
