test_that('il_cleanup() only removes tables owned by one model', {
  con <- test_con()
  withr::defer(test_discon(con))

  df_a <- data.frame(unique_id = 1:3, name = c('a', 'b', 'c'))
  df_b <- data.frame(unique_id = 1:3, name = c('a', 'a', 'd'))
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model_a <- il_model(df_a, spec = spec, con = con)
  model_b <- il_model(df_b, spec = spec, con = con)

  expect_true(DBI::dbExistsTable(con, model_a$data$tbl_l))
  expect_true(DBI::dbExistsTable(con, model_b$data$tbl_l))
  expect_false(identical(model_a$data$tbl_l, model_b$data$tbl_l))

  il_cleanup(model_a)

  expect_false(DBI::dbExistsTable(con, model_a$data$tbl_l))
  expect_true(DBI::dbExistsTable(con, model_b$data$tbl_l))
})

test_that('il_cleanup_all() removes all irelink tables on a connection', {
  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(unique_id = 1:3, name = c('a', 'b', 'c'))
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model_a <- il_model(df, spec = spec, con = con)
  model_b <- il_model(df, spec = spec, con = con)

  expect_true(DBI::dbExistsTable(con, model_a$data$tbl_l))
  expect_true(DBI::dbExistsTable(con, model_b$data$tbl_l))

  il_cleanup_all(con)

  remaining <- DBI::dbListTables(con)
  expect_false(any(grepl('^__il_', remaining)))
})

test_that('lazy prediction tables are model-prefixed and cleaned by il_cleanup()', {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(unique_id = 1:4, name = c('a', 'a', 'b', 'b'))
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 100) |>
    il_estimate_em(block_on(name))

  lazy <- predict(model, threshold = 0, collect = FALSE)

  expect_true(startsWith(lazy$predicted_tbl, paste0(model$data$table_prefix, '_')))
  expect_true(DBI::dbExistsTable(con, lazy$predicted_tbl))
  expect_true(lazy$predicted_tbl %in% lazy$model$data$tables$table)
  expect_equal(
    lazy$model$data$tables$owner[lazy$model$data$tables$table == lazy$predicted_tbl],
    'lazy'
  )

  il_cleanup(model)

  expect_false(DBI::dbExistsTable(con, lazy$predicted_tbl))
})

test_that('include_fields uses a model-scoped temporary join table', {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbWriteTable(
    con,
    '__il_field_join',
    data.frame(marker = 'sentinel'),
    overwrite = TRUE
  )

  df <- data.frame(
    unique_id = 1:4,
    name = c('a', 'a', 'b', 'b'),
    city = c('x', 'x', 'y', 'z')
  )
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 100) |>
    il_estimate_em(block_on(name))

  pairs <- predict(model, threshold = 0, include_fields = TRUE)

  expect_true(all(c('name_l', 'name_r') %in% names(pairs)))
  expect_equal(DBI::dbReadTable(con, '__il_field_join')$marker, 'sentinel')
  expect_false(any(grepl(
    paste0('^', model$data$table_prefix, '_field_join_'),
    DBI::dbListTables(con)
  )))
})
