test_that("labels_from_column derives pairwise labels from cluster column", {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  labels <- labels_from_column(model, "cluster")
  expect_true(is.data.frame(labels))
  expect_true(all(c("unique_id_l", "unique_id_r", "is_match") %in% names(labels)))
  expect_true(all(labels$is_match %in% c(0L, 1L)))
  expect_true(nrow(labels) > 0)
})

test_that("il_accuracy works with labels_col", {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  acc <- il_accuracy(model, labels_col = "cluster")
  expect_s3_class(acc, "il_accuracy")
  expect_true(nrow(acc) > 0)
  expect_true(all(c("precision", "recall", "f1") %in% names(acc)))
})

test_that("il_roc works with labels_col", {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  roc <- il_roc(model, labels_col = "cluster")
  expect_s3_class(roc, "il_roc")
})

test_that("errors when neither labels nor labels_col provided", {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  expect_error(il_accuracy(model), "labels.*labels_col")
})
