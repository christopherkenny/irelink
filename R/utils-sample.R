# Modulus for count estimates, which only need about two decimal places.
il_probe_sample_modulus <- 10000
# Modulus for EM sampling, fine enough to hit any target proportion closely.
il_em_sample_modulus <- 1e9
# Sampled pair counts below this give unstable scaled-up estimates.
il_min_sample_pairs <- 1000

#' Validate a record sampling proportion
#' @noRd
validate_record_sample_proportion <- function(
  x,
  arg = 'record_sample_proportion',
  call = rlang::caller_env()
) {
  if (
    !is.numeric(x) ||
      length(x) != 1L ||
      is.na(x) ||
      x <= 0 ||
      x > 1
  ) {
    cli::cli_abort(
      '{.arg {arg}} must be a single number in (0, 1].',
      call = call
    )
  }
  as.numeric(x)
}

#' Convert a proportion into an integer hash-bucket threshold
#' @noRd
sample_threshold <- function(proportion, modulus) {
  min(modulus, max(1, ceiling(proportion * modulus)))
}

#' Deterministic hash buckets computed in R
#'
#' Used for backends without a SQL hash function. A polynomial string hash
#' modulo the Mersenne prime 2^31 - 1 is mixed with three Park-Miller steps so
#' short or sequential ids spread evenly across buckets. All arithmetic stays
#' below 2^53, so it is exact in doubles.
#' @noRd
hash_bucket_r <- function(x, modulus) {
  p <- 2147483647
  h <- vapply(
    as.character(x),
    function(s) {
      h <- 0
      for (b in utf8ToInt(s)) {
        h <- (h * 31 + b) %% p
      }
      h
    },
    numeric(1),
    USE.NAMES = FALSE
  )
  for (i in 1:3) {
    h <- (h * 48271) %% p
  }
  floor(h / p * modulus)
}

#' Materialize a deterministic record sample of a registered table
#'
#' @param con A DBI connection.
#' @param tbl Registered table or view name with a `unique_id` column.
#' @param threshold Integer bucket threshold; rows with bucket < threshold stay.
#' @param modulus Number of hash buckets.
#' @param salt String appended to each id before hashing. A different salt
#'   draws a different sample; the empty default gives the fixed sample.
#' @return The name of a new table holding the sampled rows. The caller drops it.
#' @noRd
il_sample_records <- function(con, tbl, threshold, modulus, salt = '') {
  out <- il_scratch_table_name('sample')
  qtbl <- sql_quote_identifier(tbl)
  qout <- sql_quote_identifier(out)
  modulus_sql <- sprintf('%.0f', modulus)
  threshold_sql <- sprintf('%.0f', threshold)

  if (identical(detect_dialect(con), 'duckdb')) {
    DBI::dbExecute(
      con,
      glue::glue(
        'CREATE TABLE {qout} AS SELECT * FROM {qtbl} ',
        "WHERE hash(CAST(unique_id AS VARCHAR) || '{salt}') ",
        '% {modulus_sql} < {threshold_sql}'
      )
    )
    return(out)
  }

  ids <- DBI::dbGetQuery(
    con,
    glue::glue('SELECT unique_id FROM {qtbl}')
  )$unique_id
  keep <- ids[hash_bucket_r(paste0(ids, salt), modulus) < threshold]
  id_tbl <- il_scratch_table_name('sample_ids')
  DBI::dbWriteTable(con, id_tbl, data.frame(unique_id = keep))
  on.exit(drop_registered(con, id_tbl), add = TRUE)
  DBI::dbExecute(
    con,
    glue::glue(
      'CREATE TABLE {qout} AS SELECT * FROM {qtbl} ',
      'WHERE unique_id IN (SELECT unique_id FROM {sql_quote_identifier(id_tbl)})'
    )
  )
  out
}

#' Sample the left and right tables of a pairing
#'
#' The right table is sampled separately only when it differs from the left,
#' with its own salt so that records sharing a `unique_id` across tables are
#' kept independently and every cross-table pair has the same inclusion
#' probability.
#'
#' @return A list with sampled `tbl_l`, `tbl_r` (`NULL` when `tbl_r` was
#'   `NULL`), and `tables`, the names to drop afterwards.
#' @noRd
il_sample_table_pair <- function(
  con,
  tbl_l,
  tbl_r,
  threshold,
  modulus,
  salt = ''
) {
  sampled_l <- il_sample_records(con, tbl_l, threshold, modulus, salt)
  tables <- sampled_l
  sampled_r <- tbl_r
  if (!is.null(tbl_r)) {
    if (identical(tbl_r, tbl_l)) {
      sampled_r <- sampled_l
    } else {
      sampled_r <- il_sample_records(
        con,
        tbl_r,
        threshold,
        modulus,
        paste0(salt, '_r')
      )
      tables <- c(tables, sampled_r)
    }
  }
  list(tbl_l = sampled_l, tbl_r = sampled_r, tables = tables)
}

#' Drop sampled tables
#' @noRd
drop_sampled_tables <- function(con, tables) {
  for (tbl in tables) {
    drop_registered(con, tbl)
  }
  invisible(NULL)
}

#' Warn when a sampled pair count is too small to scale up reliably
#' @noRd
warn_small_pair_sample <- function(sampled_counts, labels) {
  small <- sampled_counts < il_min_sample_pairs
  if (any(small)) {
    cli::cli_warn(c(
      'Pair counts for {.val {labels[small]}} are estimated from fewer than {il_min_sample_pairs} sampled pairs and may be unstable.',
      i = 'Increase {.arg record_sample_proportion}, or set it to 1 for exact counts.'
    ))
  }
  invisible(NULL)
}

#' Choose a record sample that caps blocked pairs for EM
#'
#' Estimates the blocked-pair count for `blocking` from a probe sample of
#' records. When the estimate exceeds `max_pairs`, returns a copy of the model
#' whose tables hold a record sample sized so the expected blocked-pair count is
#' about `max_pairs`.
#'
#' @return A list with `model` (the model to draw EM pairs from) and `tables`
#'   (sampled table names to drop afterwards).
#' @noRd
em_pair_model <- function(model, blocking, max_pairs, probe_proportion) {
  if (is.null(max_pairs)) {
    return(list(model = model, tables = character(0)))
  }
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r
  link_type <- model$link_type %||% 'dedupe'
  dialect <- detect_dialect(con)

  probe_fraction <- 1
  probe <- list(tbl_l = tbl_l, tbl_r = tbl_r, tables = character(0))
  if (probe_proportion < 1) {
    probe_threshold <- sample_threshold(
      probe_proportion,
      il_probe_sample_modulus
    )
    probe_fraction <- probe_threshold / il_probe_sample_modulus
    probe <- il_sample_table_pair(
      con,
      tbl_l,
      tbl_r,
      probe_threshold,
      il_probe_sample_modulus
    )
  }
  probe_count <- count_unique_blocked_pairs(
    con,
    probe$tbl_l,
    probe$tbl_r,
    list(blocking),
    link_type,
    dialect
  )
  drop_sampled_tables(con, probe$tables)

  if (probe_count == 0 && probe_fraction < 1) {
    cli::cli_warn(
      'The {.arg max_pairs} probe found no blocked pairs, so EM uses all records. Increase {.arg record_sample_proportion} for a better estimate.'
    )
    return(list(model = model, tables = character(0)))
  }
  est_pairs <- probe_count / probe_fraction^2
  if (est_pairs <= max_pairs) {
    return(list(model = model, tables = character(0)))
  }

  fraction <- sqrt(max_pairs / est_pairs)
  threshold <- sample_threshold(fraction, il_em_sample_modulus)
  sampled <- il_sample_table_pair(
    con,
    tbl_l,
    tbl_r,
    threshold,
    il_em_sample_modulus
  )
  cli::cli_inform(
    'EM: blocking generates about {format(round(est_pairs), big.mark = ",")} pairs; sampling {signif(100 * fraction, 3)}% of records to cap them near {format(max_pairs, big.mark = ",", scientific = FALSE)}.'
  )
  pair_model <- model
  pair_model$data$tbl_l <- sampled$tbl_l
  pair_model$data$tbl_r <- sampled$tbl_r
  list(model = pair_model, tables = sampled$tables)
}

#' Number of candidate pairs without blocking
#' @noRd
total_pair_count <- function(model) {
  n_l <- as.numeric(model$data$n_records_l)
  n_r <- as.numeric(model$data$n_records_r %||% n_l)
  switch(model$link_type %||% 'dedupe',
    dedupe = n_l * (n_l - 1) / 2,
    link = n_l * n_r,
    link_and_dedupe = n_l * n_r + n_l * (n_l - 1) / 2 + n_r * (n_r - 1) / 2
  )
}

#' Draw a random record sample for u estimation
#'
#' When the data has more than `max_pairs` candidate pairs, samples each table
#' at proportion `sqrt(max_pairs / total)` so every pair is included with the
#' same probability and about `max_pairs` pairs remain. Otherwise uses all
#' records.
#'
#' @param salt String from R's RNG, so [set.seed()] reproduces the sample.
#' @return A list with `model` (the model to draw pairs from), `tables`
#'   (sampled table names to drop afterwards), and `expected_pairs`.
#' @noRd
u_pair_model <- function(model, max_pairs, salt) {
  total <- total_pair_count(model)
  if (total <= max_pairs) {
    return(list(model = model, tables = character(0), expected_pairs = total))
  }
  fraction <- sqrt(max_pairs / total)
  sampled <- il_sample_table_pair(
    model$con,
    model$data$tbl_l,
    model$data$tbl_r,
    sample_threshold(fraction, il_em_sample_modulus),
    il_em_sample_modulus,
    salt
  )
  pair_model <- model
  pair_model$data$tbl_l <- sampled$tbl_l
  pair_model$data$tbl_r <- sampled$tbl_r
  list(model = pair_model, tables = sampled$tables, expected_pairs = max_pairs)
}
