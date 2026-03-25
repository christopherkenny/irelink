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
    pairs <- pairs[pairs$match_probability >= threshold, , drop = FALSE]
  }

  if (method == "best_link") {
    # For each node, keep only its single highest-probability edge
    node_best <- list()
    for (i in seq_len(nrow(pairs))) {
      id_l <- as.character(pairs$unique_id_l[i])
      id_r <- as.character(pairs$unique_id_r[i])
      prob <- pairs$match_probability[i]

      if (is.null(node_best[[id_l]]) || prob > node_best[[id_l]]$prob) {
        node_best[[id_l]] <- list(partner = id_r, prob = prob, idx = i)
      }
      if (is.null(node_best[[id_r]]) || prob > node_best[[id_r]]$prob) {
        node_best[[id_r]] <- list(partner = id_l, prob = prob, idx = i)
      }
    }

    # Only keep edges where BOTH endpoints agree this is their best
    keep <- logical(nrow(pairs))
    for (i in seq_len(nrow(pairs))) {
      id_l <- as.character(pairs$unique_id_l[i])
      id_r <- as.character(pairs$unique_id_r[i])
      keep[i] <- node_best[[id_l]]$idx == i && node_best[[id_r]]$idx == i
    }
    pairs <- pairs[keep, , drop = FALSE]
  }

  # Union-Find for connected components
  parent <- setNames(all_ids, all_ids)
  rank <- setNames(rep(0L, length(all_ids)), all_ids)

  find <- function(x) {
    path <- character(0)
    while (parent[[x]] != x) {
      path <- c(path, x)
      x <- parent[[x]]
    }
    for (p in path) parent[[p]] <<- x
    x
  }

  union_nodes <- function(a, b) {
    ra <- find(a)
    rb <- find(b)
    if (ra != rb) {
      if (rank[[ra]] < rank[[rb]]) {
        parent[[ra]] <<- rb
      } else if (rank[[ra]] > rank[[rb]]) {
        parent[[rb]] <<- ra
      } else {
        parent[[rb]] <<- ra
        rank[[ra]] <<- rank[[ra]] + 1L
      }
    }
  }

  for (i in seq_len(nrow(pairs))) {
    union_nodes(as.character(pairs$unique_id_l[i]),
                as.character(pairs$unique_id_r[i]))
  }

  roots <- vapply(all_ids, find, character(1))
  unique_roots <- unique(roots)
  cluster_map <- setNames(
    paste0("cluster_", seq_along(unique_roots)),
    unique_roots
  )

  tibble::tibble(
    unique_id = all_ids,
    cluster_id = unname(cluster_map[roots])
  )
}
