#' Accuracy Metrics Across Thresholds
#'
#' Computes a full suite of classification metrics at a range of
#' match-probability thresholds. Requires labelled pairs.
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator. Required unless `labels_col` is provided.
#' @param labels_col Optional string naming a column in the original data
#'   containing ground-truth cluster/entity IDs. When provided, pairwise
#'   labels are derived automatically via [labels_from_column()].
#'
#' @return A tibble with one row per threshold, containing columns
#'   `threshold`, `tp`, `fp`, `fn`, `tn`, `fn_blocking_miss`,
#'   `precision`, `recall`, `f1`, `f2`, `f0_5`, `specificity`, `npv`,
#'   `accuracy`, `p4`, and `phi`.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c(
#'     'John', 'Jon', 'Jane', 'Jane', 'Bob',
#'     'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
#'     'John', 'Jon', 'Jane', 'Janet', 'Bob',
#'     'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
#'   ),
#'   surname = c(
#'     'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Brown', 'White', 'White',
#'     'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Browne', 'White', 'White'
#'   ),
#'   dob = c(
#'     '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
#'     '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
#'     '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
#'     '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
#'     '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
#'   ),
#'   city = c(
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
#'   ),
#'   email = c(
#'     'john@example.com', 'jon@example.com', 'jane@example.com',
#'     'jane@example.com', 'bob@example.com', 'bobby@example.com',
#'     'alice@example.com', 'alicia@example.com', 'tom@example.com',
#'     'thomas@example.com', 'john@example.com', 'jon@example.com',
#'     'jane@example.com', 'janet@example.com', 'bob@example.com',
#'     'robert@example.com', 'alice@example.com', 'alison@example.com',
#'     'tom@example.com', 'tomas@example.com'
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' labels <- data.frame(
#'   unique_id_l = c(1L, 1L),
#'   unique_id_r = c(11L, 2L),
#'   is_match = c(1L, 0L)
#' )
#'
#' il_accuracy(model, labels = labels)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_accuracy <- function(model, labels = NULL, labels_col = NULL) {
  labels <- resolve_labels(model, labels, labels_col)
  scored <- score_labeled_pairs(model, labels)
  label_probs <- scored$label_probs
  actual_positive <- scored$actual_positive
  found_by_blocking <- scored$found_by_blocking

  thresholds <- sort(unique(c(label_probs, 1)))

  results <- lapply(thresholds, function(t) {
    counts <- compute_confusion_counts(
      label_probs = label_probs,
      actual_positive = actual_positive,
      found_by_blocking = found_by_blocking,
      threshold = t
    )
    tp <- counts$tp
    fp <- counts$fp
    fn <- counts$fn
    tn <- counts$tn
    fn_blocking_miss <- counts$fn_blocking_miss

    precision <- if (tp + fp > 0) tp / (tp + fp) else 1
    recall <- if (tp + fn > 0) tp / (tp + fn) else 1
    f1 <- if (precision + recall > 0) 2 * precision * recall / (precision + recall) else 0

    # Weighted F-scores: F_beta = (1+beta^2) * P * R / (beta^2 * P + R)
    f2 <- if (precision + recall > 0) 5 * precision * recall / (4 * precision + recall) else 0
    f0_5 <- if (precision + recall > 0) 1.25 * precision * recall / (0.25 * precision + recall) else 0

    specificity <- if (tn + fp > 0) tn / (tn + fp) else 1
    npv <- if (tn + fn > 0) tn / (tn + fn) else 1
    accuracy <- if (tp + tn + fp + fn > 0) (tp + tn) / (tp + tn + fp + fn) else 1

    # P4: 4*TP*TN / ((4*TP*TN) + (TP+TN)*(FP+FN))
    p4_num <- 4 * as.numeric(tp) * tn
    p4_denom <- p4_num + as.numeric(tp + tn) * as.numeric(fp + fn)
    p4 <- if (p4_denom > 0) p4_num / p4_denom else 0

    # Phi / MCC: (TP*TN - FP*FN) / sqrt((TP+FP)*(TP+FN)*(TN+FP)*(TN+FN))
    phi_num <- as.numeric(tp) * tn - as.numeric(fp) * fn
    phi_denom <- sqrt(
      as.numeric(tp + fp) * as.numeric(tp + fn) *
        as.numeric(tn + fp) * as.numeric(tn + fn)
    )
    phi <- if (phi_denom > 0) phi_num / phi_denom else 0

    tibble::tibble(
      threshold = t, tp = tp, fp = fp, fn = fn, tn = tn,
      fn_blocking_miss = fn_blocking_miss,
      precision = precision, recall = recall, f1 = f1,
      f2 = f2, f0_5 = f0_5,
      specificity = specificity, npv = npv, accuracy = accuracy,
      p4 = p4, phi = phi
    )
  })

  do.call(rbind, results) |>
    add_class('il_accuracy')
}
