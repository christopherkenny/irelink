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

  do.call(rbind, results) |>
    add_class('il_accuracy')
}
