#' Extract Waterfall Data for a Single Pair
#'
#' Returns a tidy tibble showing how each comparison contributed to the
#' total match weight for a specific record pair. Designed for use with
#' [ggplot2::geom_col()] and [ggplot2::coord_flip()].
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param which An integer index identifying which row (pair) to
#'   decompose. Defaults to `1L`.
#'
#' @return A tibble with columns `step`, `order`, `contribution`, and
#'   `direction` (positive, negative, prior, or final).
#' @export
#'
#' @examples
#' \dontrun{
#' il_waterfall(pairs, which = 1) |>
#'   ggplot2::ggplot(ggplot2::aes(
#'     x = reorder(step, order), y = contribution, fill = direction
#'   )) +
#'   ggplot2::geom_col() +
#'   ggplot2::coord_flip()
#' }
il_waterfall <- function(pairs, which = 1L) {
  validate_il_compared(pairs)
  model <- attr(pairs, "model")
  if (is.null(model)) {
    cli::cli_abort("No model attached to the {.cls il_compared} object.")
  }

  row <- pairs[which, ]
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))

  steps <- character(length(comp_names))
  contributions <- numeric(length(comp_names))

  for (j in seq_along(comp_names)) {
    cn <- comp_names[j]
    g <- row[[paste0("gamma_", cn)]]
    m_match_j    <- params$m[params$comparison == cn & params$level == "match"]
    m_nonmatch_j <- params$m[params$comparison == cn & params$level == "non_match"]
    u_match_j    <- params$u[params$comparison == cn & params$level == "match"]
    u_nonmatch_j <- params$u[params$comparison == cn & params$level == "non_match"]

    if (g == 1L) {
      contributions[j] <- log2(pmax(m_match_j, 1e-10) / pmax(u_match_j, 1e-10))
    } else {
      contributions[j] <- log2(pmax(m_nonmatch_j, 1e-10) / pmax(u_nonmatch_j, 1e-10))
    }
    steps[j] <- cn
  }

  direction <- ifelse(contributions >= 0, "positive", "negative")

  tibble::tibble(
    step = steps,
    order = seq_along(steps),
    contribution = contributions,
    direction = direction
  )
}
