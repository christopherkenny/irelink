test_that('include_fields = TRUE adds original columns to predicted pairs', {
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

  pairs <- predict(model, threshold = 0.5, include_fields = TRUE)
  expect_true(nrow(pairs) > 0)
  # Should have _l and _r suffixed original columns
  expect_true('first_name_l' %in% names(pairs))
  expect_true('first_name_r' %in% names(pairs))
  expect_true('surname_l' %in% names(pairs))
  expect_true('surname_r' %in% names(pairs))
  expect_true('dob_l' %in% names(pairs))
  expect_true('dob_r' %in% names(pairs))
})

test_that('include_fields = TRUE works on lazy path (collect = FALSE)', {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

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

  lazy <- predict(model, threshold = 0.5, collect = FALSE, include_fields = TRUE)
  pairs <- collect_il_compared_lazy(lazy)

  expect_true(nrow(pairs) > 0)
  expect_true('first_name_l' %in% names(pairs))
  expect_true('first_name_r' %in% names(pairs))
  expect_true('surname_l' %in% names(pairs))
  expect_true('surname_r' %in% names(pairs))
})

test_that('include_fields = FALSE (default) does not add extra columns', {
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

  pairs <- predict(model, threshold = 0.5)
  expect_false('first_name_l' %in% names(pairs))
  expect_false('surname_l' %in% names(pairs))
})
