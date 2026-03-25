#' Compute Unlinkable Records
#'
#' Calculates the proportion of records that cannot be linked at each
#' match-probability threshold. Returns a tidy tibble for plotting the
#' "unlinkables curve" — useful for understanding how restrictive each
#' threshold is.
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `threshold` and `pct_unlinkable`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_unlinkables(model) |>
#'   ggplot2::ggplot(ggplot2::aes(x = threshold, y = pct_unlinkable)) +
#'   ggplot2::geom_line()
#' }
il_unlinkables <- function(model) {
  validate_il_model(model)
  all_pairs <- predict(model, threshold = 0.0)
  n_records <- model$data$n_records_l

  thresholds <- seq(0, 1, by = 0.05)

  results <- lapply(thresholds, function(t) {
    linked <- all_pairs[all_pairs$match_probability >= t, ]
    linked_ids <- unique(c(
      as.character(linked$unique_id_l),
      as.character(linked$unique_id_r)
    ))
    pct <- 1 - length(linked_ids) / n_records
    tibble::tibble(threshold = t, pct_unlinkable = pct)
  })

  do.call(rbind, results)
}
