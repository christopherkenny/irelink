test_that('il_register_tf writes TF table to database', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  # Spec without term_frequency so no auto-computed TF table
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)

  tf <- data.frame(
    first_name = c('John', 'Jane', 'Bob'),
    tf_first_name = c(0.15, 0.10, 0.05),
    stringsAsFactors = FALSE
  )
  model <- il_register_tf(model, 'first_name', tf)

  tf_tbl <- model$data$tf_tables[['first_name']]
  expect_true(tf_tbl %in% DBI::dbListTables(con))
  expect_true(startsWith(tf_tbl, model$data$table_prefix))
  stored <- DBI::dbReadTable(con, tf_tbl)
  expect_equal(nrow(stored), 3)
  expect_true('tf_first_name' %in% names(stored))
})

test_that('il_register_tf rejects wrong columns', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)

  bad_tf <- data.frame(x = 'a', y = 1)
  expect_error(il_register_tf(model, 'first_name', bad_tf))
})

test_that('il_register_tf prevents overwrite by default', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)

  tf <- data.frame(
    first_name = c('John'),
    tf_first_name = c(0.15),
    stringsAsFactors = FALSE
  )
  model <- il_register_tf(model, 'first_name', tf)
  expect_error(il_register_tf(model, 'first_name', tf))
  # But overwrite = TRUE should work
  model <- il_register_tf(model, 'first_name', tf, overwrite = TRUE)
  expect_true(model$data$tf_tables[['first_name']] %in% DBI::dbListTables(con))
})
