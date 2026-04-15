#' Confusion Matrix at a Threshold
#'
#' Computes the thresholded confusion-matrix counts for labelled pairs.
#' Uses the same SQL-first scoring path as [il_accuracy()] on supported
#' backends, so labelled pairs do not need to be predicted and collected
#' in full before evaluation.
#'
#' @param model A trained `il_model` object.
#' @param labels A data frame of labelled pairs with a logical or integer
#'   match indicator. Required unless `labels_col` is provided.
#' @param threshold A numeric value between 0 and 1 for classifying pairs
#'   as matches. Defaults to `0.85`.
#' @param labels_col Optional string naming a column in the original data
#'   containing ground-truth cluster/entity IDs. When provided, pairwise
#'   labels are derived automatically via [labels_from_column()].
#'
#' @return A one-row tibble containing `threshold`, `tp`, `fp`, `fn`,
#'   `tn`, `fn_blocking_miss`, `precision`, `recall`, and `f1`.
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
#' il_confusion_matrix(model, labels = labels, threshold = 0.85)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_confusion_matrix <- function(model, labels = NULL, threshold = 0.85,
                                labels_col = NULL) {
  labels <- resolve_labels(model, labels, labels_col)
  scored <- score_labeled_pairs(model, labels)
  counts <- compute_confusion_counts(
    label_probs = scored$label_probs,
    actual_positive = scored$actual_positive,
    found_by_blocking = scored$found_by_blocking,
    threshold = threshold
  )

  summarise_confusion_counts(counts, threshold = threshold) |>
    add_class('il_confusion_matrix')
}
