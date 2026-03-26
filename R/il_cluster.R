#' Cluster Scored Pairs into Entities
#'
#' Groups scored record pairs into entity clusters using graph-based
#' methods. Analogous to [dplyr::group_by()] — just as `group_by()`
#' assigns group labels, `il_cluster()` assigns cluster IDs to records
#' that represent the same real-world entity.
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param threshold An optional secondary match-probability threshold.
#'   If `NULL` (the default), the threshold from prediction is used.
#' @param method One of `"connected"` (default) for connected-components
#'   clustering, or `"best_link"` for single-best-link clustering.
#'
#' @return A tibble with one row per input record, including a
#'   `cluster_id` column.
#' @export
#'
#' @examples
#' \dontrun{
#' clusters <- predict(model, threshold = 0.85) |>
#'   il_cluster()
#'
#' # Count records per cluster
#' clusters |> dplyr::count(cluster_id, sort = TRUE)
#' }
il_cluster <- function(pairs, threshold = NULL,
                       method = c("connected", "best_link")) {
  method <- match.arg(method)

  if (nrow(pairs) == 0L) {
    return(tibble::tibble(unique_id = character(0), cluster_id = character(0)))
  }

  # Collect ALL unique IDs before threshold filtering
  all_ids <- unique(c(
    as.character(pairs$unique_id_l),
    as.character(pairs$unique_id_r)
  ))

  # Apply threshold filter to edges only
  if (!is.null(threshold)) {
    pairs <- pairs[which(pairs$match_probability >= threshold), , drop = FALSE]
  }

  if (method == "best_link") {
    pairs <- best_link_filter(pairs)
  }

  # Connected components via igraph (1000x faster than R union-find)
  rlang::check_installed("igraph", reason = "for clustering record pairs.")
  edges <- data.frame(
    from = as.character(pairs$unique_id_l),
    to   = as.character(pairs$unique_id_r),
    stringsAsFactors = FALSE
  )
  g <- igraph::graph_from_data_frame(
    edges, directed = FALSE,
    vertices = data.frame(name = all_ids, stringsAsFactors = FALSE)
  )
  comp <- igraph::components(g)
  cluster_map <- paste0("cluster_", comp$membership[all_ids])

  tibble::tibble(
    unique_id = all_ids,
    cluster_id = unname(cluster_map)
  )
}

# Filter edges to keep only mutual best links
# @noRd
best_link_filter <- function(pairs) {
  if (nrow(pairs) == 0L) return(pairs)
  id_l <- as.character(pairs$unique_id_l)
  id_r <- as.character(pairs$unique_id_r)
  prob  <- pairs$match_probability

  # For each node, find the index of its highest-probability edge
  all_nodes <- unique(c(id_l, id_r))
  best_idx <- setNames(rep(NA_integer_, length(all_nodes)), all_nodes)
  best_prob <- setNames(rep(-Inf, length(all_nodes)), all_nodes)

  for (i in seq_len(nrow(pairs))) {
    if (prob[i] > best_prob[id_l[i]]) {
      best_prob[id_l[i]] <- prob[i]
      best_idx[id_l[i]]  <- i
    }
    if (prob[i] > best_prob[id_r[i]]) {
      best_prob[id_r[i]] <- prob[i]
      best_idx[id_r[i]]  <- i
    }
  }

  # Keep edges where both endpoints agree
  keep <- vapply(seq_len(nrow(pairs)), function(i) {
    isTRUE(best_idx[id_l[i]] == i) && isTRUE(best_idx[id_r[i]] == i)
  }, logical(1))

  pairs[keep, , drop = FALSE]
}
