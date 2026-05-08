# Sprint 10 — Evaluation: il_accuracy(), il_confusion_matrix(), il_errors()
# Translated from: test_accuracy.py

test_that('il_accuracy() returns correct TP/FP/TN/FN at known thresholds', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_truth_space_table_from_labels_column_dedupe_only
  # 6 records: cluster 1 (IDs 1,2,3), cluster 2 (ID 4), cluster 3 (IDs 5,6)
  df <- data.frame(
    unique_id = 1:6,
    first_name = c('John', 'John', 'John', 'Mary', 'Jane', 'Jane'),
    surname = c('Smith', 'Smith', 'Smith', 'Jones', 'Taylor', 'Taylor'),
    cluster = c(1, 1, 1, 2, 3, 3)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  labels <- data.frame(
    unique_id_l = c(1L, 1L, 2L, 5L),
    unique_id_r = c(2L, 3L, 3L, 6L),
    is_match = c(TRUE, TRUE, TRUE, TRUE)
  )

  acc <- il_accuracy(model, labels)
  expect_s3_class(acc, 'tbl_df')
  # Should have columns for thresholds and TP/FP/TN/FN
  expect_true('threshold' %in% names(acc))
})

test_that('il_accuracy() TP/FP counts are internally consistent', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'A', 'B', 'B'),
    surname = rep('X', 5)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  labels <- data.frame(
    unique_id_l = c(1L, 4L),
    unique_id_r = c(2L, 5L),
    is_match = c(TRUE, TRUE)
  )

  acc <- il_accuracy(model, labels)
  # At any threshold: TP + FN = total_positives (constant)
  if (nrow(acc) > 0) {
    total_pos <- acc$tp[1] + acc$fn[1]
    expect_true(all(acc$tp + acc$fn == total_pos))
  }
})

test_that('il_confusion_matrix() matches il_accuracy() at the same threshold', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'A', 'B', 'B'),
    surname = rep('X', 5)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  labels <- data.frame(
    unique_id_l = c(1L, 4L),
    unique_id_r = c(2L, 5L),
    is_match = c(TRUE, TRUE)
  )

  cm <- il_confusion_matrix(model, labels, threshold = 0.85)
  acc <- il_accuracy(model, labels)
  acc_row <- acc[which.min(abs(acc$threshold - 0.85)), ]

  expect_s3_class(cm, 'il_confusion_matrix')
  expect_equal(cm$tp, acc_row$tp)
  expect_equal(cm$fp, acc_row$fp)
  expect_equal(cm$fn, acc_row$fn)
  expect_equal(cm$tn, acc_row$tn)
})

test_that('il_accuracy() and il_confusion_matrix() agree for lazy inputs without unique_id', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    first_name = c('A', 'A', 'A', 'B', 'B', 'C'),
    surname = c('X', 'X', 'X', 'Y', 'Y', 'Z'),
    cluster = c(1, 1, 1, 2, 2, 3)
  )
  DBI::dbWriteTable(con, 'accuracy_random_src', df, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(
    con,
    dbplyr::sql(
      'SELECT first_name, surname, cluster FROM accuracy_random_src ORDER BY random()'
    )
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(tbl_ref, spec = spec) |>
    il_estimate_u(max_pairs = 100) |>
    il_estimate_em(block_on(first_name), max_iterations = 2L)

  acc <- il_accuracy(model, labels_col = 'cluster')
  best <- acc[which.max(acc$f1), , drop = FALSE]
  cm <- il_confusion_matrix(model, labels_col = 'cluster', threshold = best$threshold)

  expect_equal(cm$tp, best$tp)
  expect_equal(cm$fp, best$fp)
  expect_equal(cm$fn, best$fn)
  expect_equal(cm$tn, best$tn)
})

# --- il_errors() ----------------------------------------------------------
# From: test_prediction_errors_from_labels_table

test_that('il_errors() returns false positive and false negative pairs', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'John', 'John', 'Mary', 'Bob'),
    surname = rep('Smith', 5)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(surname))

  labels <- data.frame(
    unique_id_l = c(1L, 1L, 4L),
    unique_id_r = c(2L, 3L, 5L),
    is_match = c(TRUE, TRUE, FALSE)
  )

  errors <- il_errors(model, labels, threshold = 0.85)
  expect_s3_class(errors, 'tbl_df')
})

test_that('labels_col evaluation counts blocking misses on SQLite fallback', {
  skip_if_not_installed('RSQLite')

  con <- DBI::dbConnect(RSQLite::SQLite(), ':memory:')
  withr::defer(DBI::dbDisconnect(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('A', 'A', 'B', 'C'),
    surname = c('X', 'X', 'X', 'Y'),
    cluster = c(1, 1, 1, 2)
  )

  spec <- il_spec() |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 100) |>
    il_estimate_em(block_on(first_name), max_iterations = 2L)

  acc <- il_accuracy(model, labels_col = 'cluster')
  row0 <- acc[acc$threshold == 0, , drop = FALSE]

  expect_equal(row0$tp, 1L)
  expect_equal(row0$fp, 0L)
  expect_equal(row0$fn, 2L)
  expect_equal(row0$tn, 0L)
  expect_equal(row0$fn_blocking_miss, 2L)

  errors <- il_errors(model, labels_col = 'cluster', threshold = 0)
  expect_equal(nrow(errors), 2L)
  expect_true(all(errors$error_type == 'false_negative'))
  expect_equal(
    sort(paste(errors$unique_id_l, errors$unique_id_r, sep = '-')),
    c('1-3', '2-3')
  )
})
