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
#' \dontrun{
#' pairs <- predict(model, threshold = 0.5)
#' clusters <- il_cluster(pairs)
#' missing <- il_score_missing_edges(model, pairs, clusters)
#' }
il_score_missing_edges <- function(model, pairs, clusters,
                                   threshold = 0) {
  validate_il_model(model)
  pairs <- ensure_collected(pairs)
  con <- model$con

  # Build set of existing scored pairs (normalised: smaller id first)
  existing_set <- unique(canonical_pair_key(pairs$unique_id_l, pairs$unique_id_r))

  # Enumerate all within-cluster pairs
  cluster_list <- split(as.character(clusters$unique_id), clusters$cluster_id)
  missing_l <- character(0)
  missing_r <- character(0)

  for (members in cluster_list) {
    if (length(members) < 2L) next
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
      unique_id_l = character(0), unique_id_r = character(0),
      match_weight = numeric(0), total_match_weight = numeric(0),
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
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  dependency_aware <- identical(model$params$estimator_mode, 'dependency-aware')
  if (!dependency_aware) {
    mu <- extract_mu_vectors(params, comp_names)
  }
  tbl_l <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl_l

  # Fetch source data for needed ids
  all_ids <- unique(c(id_l, id_r))
  id_list <- paste(DBI::dbQuoteString(con, all_ids), collapse = ', ')

  src_l <- DBI::dbGetQuery(con, glue::glue(
    'SELECT * FROM {tbl_l} WHERE unique_id IN ({id_list})'
  ))
  if (tbl_r != tbl_l) {
    src_r <- DBI::dbGetQuery(con, glue::glue(
      'SELECT * FROM {tbl_r} WHERE unique_id IN ({id_list})'
    ))
    src <- rbind(src_l, src_r)
  } else {
    src <- src_l
  }
  rownames(src) <- as.character(src$unique_id)

  n_pairs <- length(id_l)
  n_comp <- length(comparisons)
  gamma_mat <- matrix(0L, nrow = n_pairs, ncol = n_comp)
  colnames(gamma_mat) <- comp_names

  for (j in seq_len(n_comp)) {
    col <- comp_names[j]
    val_l <- src[id_l, col]
    val_r <- src[id_r, col]
    gamma_mat[, j] <- compute_gamma(val_l, val_r, comparisons[[j]]$method)
  }

  if (dependency_aware) {
    scored_patterns <- dependency_pattern_score(
      gamma_mat, comp_names, model$params$dependency_aware
    )
    match_weight <- scored_patterns$match_weight
    total_mw <- scored_patterns$total_match_weight
    match_probability <- scored_patterns$match_probability
  } else {
    match_weight <- score_gamma_matrix(gamma_mat, mu)
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

  result <- result[result$match_probability >= threshold, , drop = FALSE]
  new_il_compared(result, model = model)
}
