# Sprint 10 — ROC and precision-recall: il_roc(), il_precision_recall(),
# il_unlinkables()
# Translated from: test_accuracy.py (roc tests)

test_that('il_roc() returns a tibble with fpr and tpr in [0, 1]', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  # Use cluster column as ground truth
  labels <- data.frame(
    unique_id_l = 1:10,
    unique_id_r = 2:11,
    is_match = c(
      TRUE,
      FALSE,
      FALSE,
      TRUE,
      FALSE,
      FALSE,
      TRUE,
      FALSE,
      FALSE,
      TRUE
    )
  )

  roc <- il_roc(model, labels)
  expect_s3_class(roc, 'tbl_df')
  expect_true('fpr' %in% names(roc))
  expect_true('tpr' %in% names(roc))
  expect_true(all(roc$fpr >= 0 & roc$fpr <= 1))
  expect_true(all(roc$tpr >= 0 & roc$tpr <= 1))
})

test_that('il_roc() starts at no predicted positives', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('John', 'John', 'Jane', 'June'),
    surname = c('Smith', 'Smith', 'Doe', 'Dane'),
    cluster = c(1, 1, 2, 3)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(first_name))

  roc <- il_roc(model, labels_col = 'cluster')
  expect_true(any(roc$fpr == 0 & roc$tpr == 0))
})

test_that('il_precision_recall() returns tibble with precision and recall in [0, 1]', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  labels <- data.frame(
    unique_id_l = 1:10,
    unique_id_r = 2:11,
    is_match = c(
      TRUE,
      FALSE,
      FALSE,
      TRUE,
      FALSE,
      FALSE,
      TRUE,
      FALSE,
      FALSE,
      TRUE
    )
  )

  pr <- il_precision_recall(model, labels)
  expect_s3_class(pr, 'tbl_df')
  expect_true('precision' %in% names(pr))
  expect_true('recall' %in% names(pr))
  expect_true(all(pr$precision >= 0 & pr$precision <= 1))
  expect_true(all(pr$recall >= 0 & pr$recall <= 1))
})

test_that('il_unlinkables() returns monotonically increasing proportions', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  unl <- il_unlinkables(model)
  expect_s3_class(unl, 'tbl_df')
  expect_true('threshold' %in% names(unl))
  expect_true('pct_unlinkable' %in% names(unl))

  # Proportion should increase monotonically with threshold
  if (nrow(unl) > 1) {
    diffs <- diff(unl$pct_unlinkable)
    expect_true(all(diffs >= -0.001)) # monotonically non-decreasing (with tolerance)
  }
})

test_that('il_unlinkables() handles link models without negative proportions', {
  skip_if_not_installed('RSQLite')

  con <- DBI::dbConnect(RSQLite::SQLite(), ':memory:')
  withr::defer(DBI::dbDisconnect(con))

  df_a <- data.frame(unique_id = 1L, name = 'John')
  df_b <- data.frame(unique_id = 1L, name = 'John')

  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model <- il_model(df_a, df_b, spec = spec, con = con, link_type = 'link') |>
    il_estimate_u(max_pairs = 10) |>
    il_estimate_em(block_on(name), max_iterations = 1L)

  unl <- il_unlinkables(model)
  row0 <- unl[unl$threshold == 0, , drop = FALSE]

  expect_true(all(unl$pct_unlinkable >= 0 & unl$pct_unlinkable <= 1))
  expect_equal(row0$pct_unlinkable, 0)
})
