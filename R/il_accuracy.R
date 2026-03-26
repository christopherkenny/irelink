#' Accuracy Metrics Across Thresholds
#'
#' Computes precision, recall, F1, and counts of true positives, false
#' positives, and false negatives at a range of match-probability
#' thresholds. Requires labelled pairs.
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator.
#'
#' @return A tibble with one row per threshold, containing columns
#'   `threshold`, `precision`, `recall`, `f1`, `tp`, `fp`, and `fn`.
#' @export
#'
#' @examples
#' \dontrun{
#' il_accuracy(model, labels = labelled_pairs)
#' }
il_accuracy <- function(model, labels) {
  scored <- score_labeled_pairs(model, labels)
  label_probs <- scored$label_probs
  actual_positive <- scored$actual_positive

  thresholds <- sort(unique(c(seq(0, 1, by = 0.05))))

  results <- lapply(thresholds, function(t) {
    predicted_positive <- label_probs >= t
    tp <- sum(predicted_positive & actual_positive)
    fp <- sum(predicted_positive & !actual_positive)
    fn <- sum(!predicted_positive & actual_positive)
    tn <- sum(!predicted_positive & !actual_positive)

    precision <- if (tp + fp > 0) tp / (tp + fp) else 1
    recall <- if (tp + fn > 0) tp / (tp + fn) else 1
    f1 <- if (precision + recall > 0) 2 * precision * recall / (precision + recall) else 0

    tibble::tibble(
      threshold = t, tp = tp, fp = fp, fn = fn, tn = tn,
      precision = precision, recall = recall, f1 = f1
    )
  })

  do.call(rbind, results)
}
