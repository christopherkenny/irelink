# Internal helpers for the EM algorithm and parameter estimation.

#' Get aggregated gamma-pattern counts from blocked pairs
#'
#' Returns unique gamma patterns with their frequency counts, keeping
#' the data transfer from database to R minimal.  Used by
#' [il_estimate_em()] so it never needs the full pair-level matrix.
#'
#' @param model An il_model object.
#' @param blocking_rules List of blocking rule objects.
#' @param limit Optional integer pair limit.
#' @return A list with `counts` (data frame of gamma columns + `n`) and
#'   `n_pairs` (total pairs).
#' @noRd
get_pairs_with_gamma_counts <- function(model, blocking_rules, limit = NULL) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  gamma_cols <- paste0('gamma_', comp_names)

  if (dialect_has_fuzzy_sql(dialect)) {
    gamma_sql <- build_gamma_query(model, blocking_rules, limit = limit)
    group_by_clause <- sql_identifier_csv(gamma_cols)
    sql <- glue::glue(
      'SELECT {group_by_clause}, COUNT(*) AS n FROM ({gamma_sql}) AS pairs ',
      'GROUP BY {group_by_clause}'
    )
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0L) {
      return(list(counts = result, n_pairs = 0L))
    }
    return(list(counts = result, n_pairs = sum(result$n)))
  }

  # Fallback: pull pairs, compute gammas, aggregate counts in R
  all_pairs <- list()
  for (br in blocking_rules) {
    bp <- get_blocked_pairs(model, br)
    if (nrow(bp) > 0L) all_pairs <- c(all_pairs, list(bp))
  }
  if (length(all_pairs) == 0L) {
    empty <- as.data.frame(matrix(
      integer(0),
      nrow = 0,
      ncol = length(gamma_cols) + 1L,
      dimnames = list(NULL, c(gamma_cols, 'n'))
    ))
    return(list(counts = empty, n_pairs = 0L))
  }
  pairs <- do.call(rbind, all_pairs)
  pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = '||')
  pairs <- pairs[!duplicated(pair_key), , drop = FALSE]
  if (!is.null(limit) && nrow(pairs) > limit) {
    pairs <- pairs[seq_len(limit), , drop = FALSE]
  }
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  n_pairs <- nrow(gamma_mat)
  counts_df <- as.data.frame(gamma_mat)
  names(counts_df) <- gamma_cols
  counts <- stats::aggregate(
    list(n = rep(1L, n_pairs)),
    by = counts_df,
    FUN = sum
  )
  list(counts = counts, n_pairs = n_pairs)
}

#' Get pairs with pre-computed gamma columns
#'
#' For DuckDB: runs a single SQL query that computes gammas in-database.
#' For SQLite: falls back to pulling pairs and computing gammas in R.
#'
#' @param model An il_model object.
#' @param blocking_rules List of blocking rule objects.
#' @param limit Optional integer pair limit.
#' @return A list with `ids` (data.frame of l/r unique_id) and `gamma_mat`
#'   (integer matrix of gamma values).
#' @noRd
get_pairs_with_gammas <- function(model, blocking_rules, limit = NULL) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  tf_cols <- tf_columns(comparisons)

  if (dialect_has_fuzzy_sql(dialect)) {
    sql <- build_gamma_query(
      model,
      blocking_rules,
      limit = limit,
      deduplicate = TRUE
    )
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0L) {
      return(list(
        ids = data.frame(
          l_unique_id = integer(0),
          r_unique_id = integer(0)
        ),
        gamma_mat = matrix(
          0L,
          nrow = 0,
          ncol = length(comp_names),
          dimnames = list(NULL, comp_names)
        ),
        tf_data = NULL
      ))
    }
    ids <- result[, c('l_unique_id', 'r_unique_id'), drop = FALSE]
    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names

    # Extract TF data if present
    tf_data <- NULL
    if (length(tf_cols) > 0L) {
      tf_col_names <- c(
        paste0('tf_', tf_cols, '_l'),
        paste0('tf_', tf_cols, '_r')
      )
      present <- intersect(tf_col_names, names(result))
      if (length(present) > 0L) {
        tf_data <- result[, present, drop = FALSE]
      }
    }

    return(list(ids = ids, gamma_mat = gamma_mat, tf_data = tf_data))
  }

  # Fallback: pull pairs, compute gammas in R
  all_pairs <- list()
  for (br in blocking_rules) {
    bp <- get_blocked_pairs(model, br)
    if (nrow(bp) > 0L) all_pairs <- c(all_pairs, list(bp))
  }
  if (length(all_pairs) == 0L) {
    return(list(
      ids = data.frame(
        l_unique_id = integer(0),
        r_unique_id = integer(0)
      ),
      gamma_mat = matrix(
        0L,
        nrow = 0,
        ncol = length(comp_names),
        dimnames = list(NULL, comp_names)
      ),
      tf_data = NULL
    ))
  }
  pairs <- do.call(rbind, all_pairs)
  pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = '||')
  pairs <- pairs[!duplicated(pair_key), , drop = FALSE]
  if (!is.null(limit) && nrow(pairs) > limit) {
    pairs <- pairs[seq_len(limit), , drop = FALSE]
  }
  ids <- data.frame(
    l_unique_id = pairs$l_unique_id,
    r_unique_id = pairs$r_unique_id
  )
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  # R-side TF lookup
  tf_data <- NULL
  if (length(tf_cols) > 0L) {
    tf_data <- lookup_tf_r(model, pairs, tf_cols)
  }

  list(ids = ids, gamma_mat = gamma_mat, tf_data = tf_data)
}

#' Get random pairs with gammas (for u estimation)
#'
#' Returns gamma-level counts aggregated across a random sample of pairs,
#' rather than the full pair matrix, to keep data transfer small.
#'
#' @param model An il_model object.
#' @param max_pairs Maximum pairs to sample.
#' @return A list with `counts` (data frame of gamma columns + `n`) and
#'   `n_pairs` (total sampled pairs).
#' @noRd
get_random_pairs_with_gammas <- function(
  model,
  max_pairs = 1e6,
  profile = NULL
) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  gamma_cols <- paste0('gamma_', comp_names)

  if (dialect_has_fuzzy_sql(dialect)) {
    tbl_l <- model$data$tbl_l
    tbl_r <- tbl_l
    if (!is.null(model$data$tbl_r)) {
      tbl_r <- model$data$tbl_r
    }
    link_type <- model$link_type %||% 'dedupe'
    has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l
    max_pairs <- as.integer(max_pairs)

    gamma_exprs <- vapply(
      comparisons,
      function(comp) {
        expr <- sql_gamma_case(comp, dialect)
        glue::glue(
          '{expr} AS {sql_quote_identifier(paste0("gamma_", comparison_name(comp)))}'
        )
      },
      character(1)
    )
    gamma_select <- paste(gamma_exprs, collapse = ', ')
    group_by_clause <- sql_identifier_csv(gamma_cols)

    table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
    parts <- vapply(
      table_pairs,
      function(tp) {
        glue::glue(
          'SELECT {gamma_select} ',
          'FROM {sql_quote_identifier(tp$from_l)} l, {sql_quote_identifier(tp$from_r)} r ',
          'WHERE {tp$join_cond}'
        )
      },
      character(1)
    )
    inner <- paste(parts, collapse = ' UNION ALL ')

    sql <- glue::glue(
      'SELECT {group_by_clause}, COUNT(*) AS n FROM (',
      'SELECT * FROM ({inner}) AS pairs LIMIT {max_pairs}',
      ') AS sampled GROUP BY {group_by_clause}'
    )
    result <- il_db_get_query(
      con,
      sql,
      step = 'estimate_u.random_pair_gamma_counts',
      profile = profile
    )
    if (nrow(result) == 0L) {
      return(list(counts = result, n_pairs = 0L))
    }
    return(list(counts = result, n_pairs = sum(result$n)))
  }

  # Fallback: R-side — pull pairs, compute gammas, aggregate counts in R
  pairs <- get_all_pairs(model, max_pairs = max_pairs)
  if (nrow(pairs) == 0L) {
    empty <- as.data.frame(matrix(
      integer(0),
      nrow = 0,
      ncol = length(gamma_cols) + 1L,
      dimnames = list(NULL, c(gamma_cols, 'n'))
    ))
    return(list(counts = empty, n_pairs = 0L))
  }
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)
  n_pairs <- nrow(gamma_mat)
  counts_df <- as.data.frame(gamma_mat)
  names(counts_df) <- gamma_cols
  counts <- stats::aggregate(
    list(n = rep(1L, n_pairs)),
    by = counts_df,
    FUN = sum
  )
  list(counts = counts, n_pairs = n_pairs)
}

#' Get random-pair gamma counts in chunks
#'
#' Accumulates the same gamma-pattern counts as
#' `get_random_pairs_with_gammas()`, but queries or processes at most
#' `chunk_size` candidate pairs at a time and can stop early once every
#' comparison level has enough support.
#'
#' @param model An il_model object.
#' @param max_pairs Maximum pairs to sample.
#' @param chunk_size Number of pairs per chunk.
#' @param min_count_per_level Optional early-stop support target.
#' @return A list with `counts`, `n_pairs`, `stopped_early`, and `n_chunks`.
#' @noRd
get_random_pair_gamma_counts_chunked <- function(
  model,
  max_pairs,
  chunk_size,
  min_count_per_level = NULL,
  profile = NULL
) {
  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  comp_names <- comparison_names(comparisons)
  gamma_cols <- paste0('gamma_', comp_names)

  counts <- empty_gamma_counts(gamma_cols)
  n_pairs <- 0L
  n_chunks <- 0L
  stopped_early <- FALSE

  if (dialect_has_fuzzy_sql(dialect)) {
    tbl_l <- model$data$tbl_l
    tbl_r <- tbl_l
    if (!is.null(model$data$tbl_r)) {
      tbl_r <- model$data$tbl_r
    }
    link_type <- model$link_type %||% 'dedupe'
    has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

    gamma_exprs <- vapply(
      comparisons,
      function(comp) {
        expr <- sql_gamma_case(comp, dialect)
        glue::glue(
          '{expr} AS {sql_quote_identifier(paste0("gamma_", comparison_name(comp)))}'
        )
      },
      character(1)
    )
    gamma_select <- paste(gamma_exprs, collapse = ', ')
    group_by_clause <- sql_identifier_csv(gamma_cols)

    table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
    parts <- vapply(
      table_pairs,
      function(tp) {
        glue::glue(
          'SELECT {gamma_select} ',
          'FROM {sql_quote_identifier(tp$from_l)} l, {sql_quote_identifier(tp$from_r)} r ',
          'WHERE {tp$join_cond}'
        )
      },
      character(1)
    )
    inner <- paste(parts, collapse = ' UNION ALL ')

    offset <- 0L
    while (n_pairs < max_pairs) {
      this_limit <- min(chunk_size, max_pairs - n_pairs)
      sql <- glue::glue(
        'SELECT {group_by_clause}, COUNT(*) AS n FROM (',
        'SELECT * FROM ({inner}) AS pairs ',
        'LIMIT {this_limit} OFFSET {offset}',
        ') AS sampled GROUP BY {group_by_clause}'
      )
      chunk_counts <- il_db_get_query(
        con,
        sql,
        step = 'estimate_u.random_pair_gamma_counts_chunk',
        profile = profile
      )
      chunk_n <- sum(chunk_counts$n)
      if (nrow(chunk_counts) == 0L) {
        chunk_n <- 0L
      }
      if (chunk_n == 0L) {
        break
      }
      counts <- combine_gamma_counts(counts, chunk_counts, gamma_cols)
      n_pairs <- n_pairs + chunk_n
      n_chunks <- n_chunks + 1L
      offset <- offset + chunk_n
      if (
        gamma_support_met(
          counts,
          comparisons,
          comp_names,
          min_count_per_level
        )
      ) {
        stopped_early <- TRUE
        break
      }
    }
    return(list(
      counts = counts,
      n_pairs = n_pairs,
      stopped_early = stopped_early,
      n_chunks = n_chunks
    ))
  }

  pairs <- get_all_pairs(model, max_pairs = max_pairs)
  if (nrow(pairs) == 0L) {
    return(list(
      counts = counts,
      n_pairs = 0L,
      stopped_early = FALSE,
      n_chunks = 0L
    ))
  }
  start <- 1L
  while (start <= nrow(pairs) && n_pairs < max_pairs) {
    end <- min(start + chunk_size - 1L, nrow(pairs), max_pairs)
    chunk_pairs <- pairs[start:end, , drop = FALSE]
    gamma_mat <- compute_gamma_matrix(chunk_pairs, comparisons)
    chunk_counts <- gamma_matrix_counts(gamma_mat, gamma_cols)
    counts <- combine_gamma_counts(counts, chunk_counts, gamma_cols)
    chunk_n <- nrow(gamma_mat)
    n_pairs <- n_pairs + chunk_n
    n_chunks <- n_chunks + 1L
    if (
      gamma_support_met(
        counts,
        comparisons,
        comp_names,
        min_count_per_level
      )
    ) {
      stopped_early <- TRUE
      break
    }
    start <- end + 1L
  }

  list(
    counts = counts,
    n_pairs = n_pairs,
    stopped_early = stopped_early,
    n_chunks = n_chunks
  )
}

#' Register a materialized blocked-pairs table for a model
#'
#' The table contains unique pair identifiers only, not source fields:
#' `source_l`, `l_unique_id`, `source_r`, and `r_unique_id`.
#'
#' @param model An il_model object.
#' @param blocking_rules Blocking rules to materialize.
#' @param purpose Registry name, usually "predict".
#' @param overwrite If FALSE, create a uniquely suffixed table. If TRUE, reuse
#'   and replace the purpose-specific table.
#' @return The updated model.
#' @noRd
register_blocked_pairs <- function(
  model,
  blocking_rules = model$spec$blocking_rules,
  purpose = 'predict',
  overwrite = FALSE
) {
  validate_il_model(model)
  if (!is.list(blocking_rules)) {
    cli::cli_abort('{.arg blocking_rules} must be a list of blocking rules.')
  }
  if (length(blocking_rules) == 0L) {
    cli::cli_abort(
      'At least one blocking rule is required to register blocked pairs.'
    )
  }
  bad <- !vapply(
    blocking_rules,
    inherits,
    logical(1),
    what = 'il_blocking_rule'
  )
  if (any(bad)) {
    cli::cli_abort(
      '{.arg blocking_rules} must contain only {.cls il_blocking_rule} objects.'
    )
  }

  con <- model$con
  dialect <- detect_dialect(con)
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l
  suffix <- il_table_suffix()
  if (isTRUE(overwrite)) {
    suffix <- NULL
  }
  tbl <- il_table_name(model, paste0('blocked_pairs_', purpose), suffix)

  parts <- vapply(
    blocking_rules,
    function(rule) {
      blocked_pair_rows_sql(
        tbl_l,
        tbl_r,
        rule,
        link_type,
        has_two_tables,
        dialect
      )
    },
    character(1)
  )
  union_sql <- paste(parts, collapse = ' UNION ALL ')
  sql <- glue::glue(
    'CREATE TABLE {tbl} AS ',
    'SELECT DISTINCT source_l, unique_id_l AS l_unique_id, ',
    'source_r, unique_id_r AS r_unique_id ',
    'FROM ({union_sql}) AS blocked_pairs'
  )
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl}'))
  DBI::dbExecute(con, sql)

  if (is.null(model$data$blocked_pairs)) {
    model$data$blocked_pairs <- list()
  }
  model$data$blocked_pairs[[purpose]] <- tbl
  model <- il_track_table(model, tbl, owner = 'model')
  model
}

#' Empty gamma-count table
#' @noRd
empty_gamma_counts <- function(gamma_cols) {
  as.data.frame(matrix(
    integer(0),
    nrow = 0,
    ncol = length(gamma_cols) + 1L,
    dimnames = list(NULL, c(gamma_cols, 'n'))
  ))
}

#' Aggregate a gamma matrix into pattern counts
#' @noRd
gamma_matrix_counts <- function(gamma_mat, gamma_cols) {
  if (nrow(gamma_mat) == 0L) {
    return(empty_gamma_counts(gamma_cols))
  }
  counts_df <- as.data.frame(gamma_mat)
  names(counts_df) <- gamma_cols
  stats::aggregate(
    list(n = rep(1L, nrow(gamma_mat))),
    by = counts_df,
    FUN = sum
  )
}

#' Combine gamma-pattern count tables
#' @noRd
combine_gamma_counts <- function(current, chunk, gamma_cols) {
  if (nrow(chunk) == 0L) {
    return(current)
  }
  if (nrow(current) == 0L) {
    chunk <- chunk[, c(gamma_cols, 'n'), drop = FALSE]
    return(chunk)
  }
  combined <- rbind(
    current[, c(gamma_cols, 'n'), drop = FALSE],
    chunk[, c(gamma_cols, 'n'), drop = FALSE]
  )
  stats::aggregate(
    list(n = combined$n),
    by = combined[, gamma_cols, drop = FALSE],
    FUN = sum
  )
}

#' Test whether all comparison levels have enough sampled support
#' @noRd
gamma_support_met <- function(
  counts,
  comparisons,
  comp_names,
  min_count_per_level
) {
  if (is.null(min_count_per_level) || nrow(counts) == 0L) {
    return(FALSE)
  }
  for (j in seq_along(comp_names)) {
    gcol <- paste0('gamma_', comp_names[j])
    if (gcol %in% names(counts)) {
      counts[[gcol]][is.na(counts[[gcol]])] <- 0L
    }
    n_levels <- n_gamma_levels(comparisons[[j]]$method)
    for (k in seq(0L, n_levels - 1L)) {
      count_k <- sum(counts$n[counts[[gcol]] == k], na.rm = TRUE)
      if (count_k < min_count_per_level) {
        return(FALSE)
      }
    }
  }
  TRUE
}

#' Compute multi-level gamma for a pair of values
#' @param val_l Left record values (vector).
#' @param val_r Right record values (vector).
#' @param comp_level An il_comparison_level object.
#' @return Integer vector: 0 (else) through K (best match).
#' @noRd
compute_gamma <- function(val_l, val_r, comp_level) {
  method <- comp_level$method
  n <- length(val_l)
  both_present <- !is.na(val_l) & !is.na(val_r)

  if (method == 'exact') {
    return(ifelse(both_present & val_l == val_r, 1L, 0L))
  }

  # Multi-threshold: loop from most lenient to strictest, overwriting
  # with higher gamma levels. Thresholds are stored strictest-first.
  thresholds <- comp_level$thresholds

  if (method %in% c('levenshtein', 'damerau_levenshtein')) {
    dist <- rep(NA_real_, n)
    dist[both_present] <- stringdist::stringdist(
      as.character(val_l[both_present]),
      as.character(val_r[both_present]),
      method = 'lv'
    )
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[both_present & !is.na(dist) & dist <= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method %in% c('jaro_winkler', 'jaro')) {
    p <- 0
    if (method == 'jaro_winkler') {
      p <- 0.1
    }
    score <- rep(NA_real_, n)
    score[both_present] <- 1 -
      stringdist::stringdist(
        as.character(val_l[both_present]),
        as.character(val_r[both_present]),
        method = 'jw',
        p = p
      )
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[both_present & !is.na(score) & score >= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method %in% c('jaccard', 'cosine')) {
    sd_method <- 'cosine'
    if (method == 'jaccard') {
      sd_method <- 'jaccard'
    }
    score <- rep(NA_real_, n)
    score[both_present] <- 1 -
      stringdist::stringdist(
        as.character(val_l[both_present]),
        as.character(val_r[both_present]),
        method = sd_method,
        q = 2
      )
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[both_present & !is.na(score) & score >= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method %in% c('numeric_diff', 'pct_diff')) {
    num_l <- suppressWarnings(as.numeric(val_l))
    num_r <- suppressWarnings(as.numeric(val_r))
    bp <- !is.na(num_l) & !is.na(num_r)
    if (method == 'numeric_diff') {
      diff <- abs(num_l - num_r)
    } else {
      denom <- pmax(abs(num_l), abs(num_r))
      denom[denom == 0] <- NA_real_
      diff <- abs(num_l - num_r) / denom
    }
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[bp & !is.na(diff) & diff <= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method == 'geo_distance') {
    lat_l <- val_l[[1]]
    lon_l <- val_l[[2]]
    lat_r <- val_r[[1]]
    lon_r <- val_r[[2]]
    lat_l <- suppressWarnings(as.numeric(lat_l))
    lon_l <- suppressWarnings(as.numeric(lon_l))
    lat_r <- suppressWarnings(as.numeric(lat_r))
    lon_r <- suppressWarnings(as.numeric(lon_r))
    bp <- !is.na(lat_l) & !is.na(lon_l) & !is.na(lat_r) & !is.na(lon_r)
    rad <- pi / 180
    dlat <- (lat_r - lat_l) * rad
    dlon <- (lon_r - lon_l) * rad
    a <- sin(dlat / 2)^2 + cos(lat_l * rad) * cos(lat_r * rad) * sin(dlon / 2)^2
    dist <- 2 * 6371 * asin(sqrt(a))
    gamma <- rep(0L, length(lat_l))
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      level_code <- nt - i + 1L
      gamma[bp & !is.na(dist) & dist <= thresholds[i]] <- level_code
    }
    return(gamma)
  }

  if (method == 'date_diff') {
    date_l <- suppressWarnings(as.Date(val_l))
    date_r <- suppressWarnings(as.Date(val_r))
    bp <- !is.na(date_l) & !is.na(date_r)
    diff <- abs(as.numeric(date_l - date_r))
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      unit <- comp_level$units[i]
      mult <- switch(unit, 'days' = 1, 'months' = 30, 'years' = 365, 1)
      days_thresh <- thresholds[i] * mult
      level_code <- nt - i + 1L
      gamma[bp & !is.na(diff) & diff <= days_thresh] <- level_code
    }
    return(gamma)
  }

  if (method == 'time_diff') {
    ts_l <- suppressWarnings(as.POSIXct(val_l))
    ts_r <- suppressWarnings(as.POSIXct(val_r))
    bp <- !is.na(ts_l) & !is.na(ts_r)
    diff_secs <- abs(as.numeric(difftime(ts_l, ts_r, units = 'secs')))
    gamma <- rep(0L, n)
    nt <- length(thresholds)
    for (i in rev(seq_along(thresholds))) {
      secs_thresh <- time_diff_to_seconds(thresholds[i], comp_level$units[i])
      level_code <- nt - i + 1L
      gamma[bp & !is.na(diff_secs) & diff_secs <= secs_thresh] <- level_code
    }
    return(gamma)
  }

  if (method == 'soundex') {
    sx_l <- il_soundex(as.character(val_l))
    sx_r <- il_soundex(as.character(val_r))
    return(ifelse(
      both_present & !is.na(sx_l) & !is.na(sx_r) & sx_l == sx_r,
      1L,
      0L
    ))
  }

  if (method == 'array_min_distance') {
    fn <- comp_level$fn
    thresholds <- comp_level$thresholds
    n <- length(thresholds)
    sd_method <- 'lv'
    sd_p <- 0
    if (fn == 'jaro_winkler') {
      sd_method <- 'jw'
      sd_p <- 0.1
    }

    gamma <- rep(0L, length(val_l))
    for (k in seq_len(length(val_l))) {
      if (is.na(val_l[k]) || is.na(val_r[k])) {
        next
      }
      a <- unique(trimws(unlist(strsplit(
        as.character(val_l[k]),
        ',',
        fixed = TRUE
      ))))
      b <- unique(trimws(unlist(strsplit(
        as.character(val_r[k]),
        ',',
        fixed = TRUE
      ))))
      pairs_a <- rep(a, each = length(b))
      pairs_b <- rep(b, times = length(a))
      dists <- stringdist::stringdist(
        pairs_a,
        pairs_b,
        method = sd_method,
        p = sd_p
      )
      best <- min(dists)
      if (fn == 'jaro_winkler') {
        best <- max(1 - dists)
      }
      # Iterate most-lenient to strictest; overwrite with higher gamma each time
      # a stricter threshold is also satisfied. Matches the pattern in jaro_winkler
      # and levenshtein handling above.
      for (i in rev(seq_along(thresholds))) {
        level_code <- n - i + 1L
        passes <- best <= thresholds[i]
        if (fn == 'jaro_winkler') {
          passes <- best >= thresholds[i]
        }
        if (passes) {
          gamma[k] <- level_code
        }
      }
    }
    return(gamma)
  }

  if (method == 'array_subset') {
    result <- mapply(
      function(a, b) {
        if (is.na(a) || is.na(b)) {
          return(0L)
        }
        a_set <- unique(unlist(strsplit(as.character(a), ',\\s*')))
        b_set <- unique(unlist(strsplit(as.character(b), ',\\s*')))
        if (all(a_set %in% b_set) || all(b_set %in% a_set)) 1L else 0L
      },
      val_l,
      val_r
    )
    return(as.integer(result))
  }

  if (method == 'array_intersect') {
    result <- mapply(
      function(a, b) {
        if (is.na(a) || is.na(b)) {
          return(0L)
        }
        a_set <- unique(unlist(strsplit(as.character(a), ',\\s*')))
        b_set <- unique(unlist(strsplit(as.character(b), ',\\s*')))
        shared <- length(intersect(a_set, b_set))
        gamma <- 0L
        nt <- length(thresholds)
        for (i in rev(seq_along(thresholds))) {
          if (shared >= thresholds[i]) {
            gamma <- nt - i + 1L
          }
        }
        gamma
      },
      val_l,
      val_r
    )
    return(as.integer(result))
  }

  if (method == 'levels') {
    has_null_level <- any(vapply(
      comp_level$levels,
      function(l) {
        isTRUE(l$is_null_level)
      },
      logical(1)
    ))

    # Check sublevels from best to worst (skip null/else)
    sublevels <- Filter(
      function(l) {
        !isTRUE(l$is_null_level) && !isTRUE(l$is_else_level)
      },
      comp_level$levels
    )
    nsub <- length(sublevels)
    if (nsub == 0L) {
      gamma <- ifelse(both_present & val_l == val_r, 1L, 0L)
      if (has_null_level) {
        gamma[!both_present] <- -1L
      }
      return(gamma)
    }
    gamma <- rep(0L, n)
    if (has_null_level) {
      gamma[!both_present] <- -1L
    }
    for (i in rev(seq_along(sublevels))) {
      sub_gamma <- compute_gamma(val_l, val_r, sublevels[[i]])
      level_code <- nsub - i + 1L
      gamma[sub_gamma > 0L] <- level_code
    }
    return(gamma)
  }

  if (method == 'and') {
    child_mat <- vapply(
      comp_level$children,
      function(child) {
        compute_gamma(val_l, val_r, child) > 0L
      },
      logical(n)
    )
    return(as.integer(rowSums(child_mat) == length(comp_level$children)))
  }

  if (method == 'or') {
    child_mat <- vapply(
      comp_level$children,
      function(child) {
        compute_gamma(val_l, val_r, child) > 0L
      },
      logical(n)
    )
    return(as.integer(rowSums(child_mat) > 0L))
  }

  if (method == 'not') {
    return(as.integer(
      compute_gamma(val_l, val_r, comp_level$child) <= 0L & both_present
    ))
  }

  if (method == 'custom') {
    cli::cli_abort(
      '{.fn cl_custom} requires SQL gamma computation and is not supported by the R fallback path.'
    )
  }

  # Fallback: exact match
  ifelse(both_present & val_l == val_r, 1L, 0L)
}

#' Get blocked pairs from the database as a data frame
#' @param model An il_model object.
#' @param blocking An il_blocking_rule object.
#' @return A data frame with columns from both left and right records.
#' @noRd
get_blocked_pairs <- function(model, blocking) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- tbl_l
  if (!is.null(model$data$tbl_r)) {
    tbl_r <- model$data$tbl_r
  }
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

  cols <- model$data$columns
  sel <- build_select_aliases(cols)
  block_where <- build_blocking_condition(
    blocking$columns,
    blocking$where,
    transform = blocking$transform,
    dialect = detect_dialect(con)
  )

  table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
  parts <- vapply(
    table_pairs,
    function(tp) {
      where_clause <- tp$join_cond
      if (nzchar(block_where)) {
        where_clause <- glue::glue('{tp$join_cond} AND {block_where}')
      }
      glue::glue(
        'SELECT {sel$left}, {sel$right} FROM {sql_quote_identifier(tp$from_l)} l, {sql_quote_identifier(tp$from_r)} r ',
        'WHERE {where_clause}'
      )
    },
    character(1)
  )
  sql <- paste(parts, collapse = ' UNION ALL ')

  DBI::dbGetQuery(con, sql)
}

#' Get all pairs (no blocking) from the database
#' @noRd
get_all_pairs <- function(model, max_pairs = 1e6) {
  con <- model$con
  tbl_l <- model$data$tbl_l
  tbl_r <- tbl_l
  if (!is.null(model$data$tbl_r)) {
    tbl_r <- model$data$tbl_r
  }
  link_type <- model$link_type %||% 'dedupe'
  has_two_tables <- !is.null(model$data$tbl_r) && model$data$tbl_r != tbl_l

  cols <- model$data$columns
  sel <- build_select_aliases(cols)

  max_pairs <- as.integer(max_pairs)
  table_pairs <- build_table_pairs(tbl_l, tbl_r, link_type, has_two_tables)
  parts <- vapply(
    table_pairs,
    function(tp) {
      glue::glue(
        'SELECT {sel$left}, {sel$right} FROM {sql_quote_identifier(tp$from_l)} l, {sql_quote_identifier(tp$from_r)} r ',
        'WHERE {tp$join_cond}'
      )
    },
    character(1)
  )
  sql <- paste(parts, collapse = ' UNION ALL ')
  sql <- glue::glue('{sql} LIMIT {max_pairs}')

  DBI::dbGetQuery(con, sql)
}

#' Compute gamma matrix for pairs
#' @param pairs Data frame of pairs.
#' @param comparisons List of comparison entries from spec.
#' @return An integer matrix (n_pairs x n_comparisons).
#' @noRd
compute_gamma_matrix <- function(pairs, comparisons) {
  n_comp <- length(comparisons)
  n_pairs <- nrow(pairs)

  gamma_mat <- matrix(0L, nrow = n_pairs, ncol = n_comp)

  for (j in seq_len(n_comp)) {
    comp <- comparisons[[j]]
    col <- comp$columns
    if (length(col) == 2L && identical(comp$method$method, 'geo_distance')) {
      val_l <- pairs[paste0('l_', col)]
      val_r <- pairs[paste0('r_', col)]
    } else {
      val_l <- pairs[[paste0('l_', col)]]
      val_r <- pairs[[paste0('r_', col)]]
    }
    # Apply transform if specified
    if (!is.null(comp$transform)) {
      val_l <- comp$transform(val_l)
      val_r <- comp$transform(val_r)
    }
    gamma_mat[, j] <- compute_gamma(val_l, val_r, comp$method)
  }

  colnames(gamma_mat) <- comparison_names(comparisons)
  gamma_mat
}
