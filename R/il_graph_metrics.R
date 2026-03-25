#' Compute Graph Metrics for Clusters
#'
#' Returns node-, edge-, and cluster-level metrics from the linkage
#' graph. Useful for diagnosing cluster quality and identifying bridge
#' edges or weakly connected components.
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param clusters A tibble from [il_cluster()] with cluster assignments.
#'
#' @return A named list of three tibbles:
#'   \describe{
#'     \item{`nodes`}{Record-level metrics (degree, centrality).}
#'     \item{`edges`}{Edge-level metrics (match probability, bridge flag).}
#'     \item{`clusters`}{Cluster-level metrics (size, density).}
#'   }
#' @export
#'
#' @examples
#' \dontrun{
#' pairs <- predict(model, threshold = 0.85)
#' clusters <- il_cluster(pairs)
#' metrics <- il_graph_metrics(pairs, clusters)
#' metrics$clusters
#' }
il_graph_metrics <- function(pairs, clusters) {
  cli::cli_warn("Function {.fn il_graph_metrics} is not yet implemented.")
  invisible(NULL)
}
