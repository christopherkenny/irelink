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
  cli::cli_warn("Function {.fn il_cluster} is not yet implemented.")
  invisible(NULL)
}
