#' Score Missing Edges Within Clusters
#'
#' Identifies pairs of records within the same cluster that were not
#' already scored during prediction (e.g. because they were in different
#' blocking groups), and scores them using the model. This can reveal
#' low-confidence links that bridge otherwise separate sub-clusters.
#'
#' @param model A trained `il_model` object.
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param clusters A tibble from [il_cluster()] with columns `unique_id`
#'   and `cluster_id`.
#' @param threshold Numeric match-probability threshold for returned
#'   pairs. Defaults to `0`.
#'
#' @return An `il_compared` tibble of newly scored pairs (those not
#'   already in `pairs`).
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = c(1, 2, 3),
#'   first_name = c('John', 'John', 'Jon'),
#'   surname = c('Smith', 'Smyth', 'Smith')
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_exact()) |>
#'   il_compare(surname, cl_exact()) |>
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' pairs <- predict(model, threshold = 0.01)
#' clusters <- tibble::tibble(
#'   unique_id = c('1', '2', '3'),
#'   cluster_id = 'cluster_1'
#' )
#' missing <- il_score_missing_edges(model, pairs, clusters)
#' il_cleanup(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_score_missing_edges <- function(model, pairs, clusters, threshold = 0) {
  validate_trained_model(model)
  threshold <- validate_probability_threshold(threshold, 'threshold')
  pairs <- ensure_collected(pairs)
  validate_il_compared(pairs)
  required_cluster_cols <- c('unique_id', 'cluster_id')
  missing_cluster_cols <- setdiff(required_cluster_cols, names(clusters))
  if (length(missing_cluster_cols) > 0L) {
    cli::cli_abort(
      '{.arg clusters} must contain column{?s} {.field {missing_cluster_cols}}.'
    )
  }
  required_pair_cols <- c('unique_id_l', 'unique_id_r')
  missing_pair_cols <- setdiff(required_pair_cols, names(pairs))
  if (length(missing_pair_cols) > 0L) {
    cli::cli_abort(
      '{.arg pairs} must contain column{?s} {.field {missing_pair_cols}}.'
    )
  }
  con <- model$con

  # Build set of existing scored pairs (normalised: smaller id first)
  existing_set <- unique(canonical_pair_key(
    pairs$unique_id_l,
    pairs$unique_id_r
  ))

  # Enumerate all within-cluster pairs
  cluster_list <- split(as.character(clusters$unique_id), clusters$cluster_id)
  missing_l <- character(0)
  missing_r <- character(0)

  for (members in cluster_list) {
    if (length(members) < 2L) {
      next
    }
    combos <- utils::combn(sort(members), 2)
    keys <- canonical_pair_key(combos[1, ], combos[2, ])
    new_mask <- !(keys %in% existing_set)
    if (any(new_mask)) {
      missing_l <- c(missing_l, combos[1, new_mask])
      missing_r <- c(missing_r, combos[2, new_mask])
    }
  }

  if (length(missing_l) == 0L) {
    empty <- tibble::tibble(
      unique_id_l = character(0),
      unique_id_r = character(0),
      match_weight = numeric(0),
      total_match_weight = numeric(0),
      match_probability = numeric(0)
    )
    return(new_il_compared(empty, model = model))
  }

  # Score the missing pairs
  score_specific_pairs(model, missing_l, missing_r, threshold)
}

#' Score a specific set of id pairs using the model
#' @noRd
score_specific_pairs <- function(model, id_l, id_r, threshold = 0) {
  con <- model$con
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- safe_prior(model)
  comp_names <- comparison_names(comparisons)
  dependency_aware <- identical(model$params$estimator_mode, 'dependency-aware')
  if (!dependency_aware) {
    mu <- extract_mu_vectors(params, comp_names)
  }
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  id_l <- as.character(id_l)
  id_r <- as.character(id_r)
  src_l <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {tbl_l}'))
  src_r <- src_l
  if (tbl_r != tbl_l) {
    src_r <- DBI::dbGetQuery(con, glue::glue('SELECT * FROM {tbl_r}'))
  }
  rownames(src_l) <- as.character(src_l$unique_id)
  rownames(src_r) <- as.character(src_r$unique_id)

  if (!all((id_l %in% rownames(src_l))) || !all((id_r %in% rownames(src_r)))) {
    cli::cli_abort(
      'Could not find every requested pair ID in the model source tables.'
    )
  }

  n_pairs <- length(id_l)
  pair_data <- data.frame(row_idx = seq_len(n_pairs))
  needed_cols <- unique(unlist(lapply(comparisons, function(comp) {
    comp$columns
  })))
  for (col in needed_cols) {
    pair_data[[paste0('l_', col)]] <- src_l[id_l, col]
    pair_data[[paste0('r_', col)]] <- src_r[id_r, col]
  }
  gamma_mat <- compute_gamma_matrix(pair_data, comparisons)

  tf_adj_list <- NULL
  tf_adj <- numeric(n_pairs)
  if (!dependency_aware) {
    tf_cols <- tf_columns(comparisons)
    if (length(tf_cols) > 0L) {
      tf_data <- lookup_tf_r(model, pair_data, tf_cols)
      tf_adj <- compute_tf_adjustment(gamma_mat, tf_data, comparisons, mu)
      tf_adj_list <- compute_tf_adjustment_matrix(
        gamma_mat,
        tf_data,
        comparisons,
        mu
      )
    }
  }

  if (dependency_aware) {
    scored_patterns <- dependency_pattern_score(
      gamma_mat,
      comp_names,
      model$params$dependency_aware
    )
    match_weight <- scored_patterns$match_weight
    total_mw <- scored_patterns$total_match_weight
    match_probability <- scored_patterns$match_probability
  } else {
    match_weight <- score_gamma_matrix(gamma_mat, mu)
    match_weight <- match_weight + tf_adj
    total_mw <- total_match_weight(match_weight, prior)
    match_probability <- weight_to_probability(match_weight, prior)
  }

  result <- tibble::tibble(
    unique_id_l = id_l,
    unique_id_r = id_r,
    match_weight = match_weight,
    total_match_weight = total_mw,
    match_probability = match_probability
  )
  for (j in seq_along(comp_names)) {
    result[[paste0('gamma_', comp_names[j])]] <- gamma_mat[, j]
  }
  if (!is.null(tf_adj_list)) {
    for (col in names(tf_adj_list)) {
      result[[paste0('tf_adj_', col)]] <- tf_adj_list[[col]]
    }
  }

  result <- result[result$match_probability >= threshold, , drop = FALSE]
  new_il_compared(result, model = model)
}
