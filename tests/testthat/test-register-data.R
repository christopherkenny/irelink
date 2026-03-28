# Tests for register_data() — database connection support

test_that('register_data handles data.frame input', {
  con <- test_con()
  on.exit(test_discon(con))

  reg <- irelink:::register_data(fake_20, con = con, tbl_name = '__test_df')
  on.exit(irelink:::drop_registered(con, '__test_df'), add = TRUE, after = FALSE)


  expect_equal(reg$tbl_name, '__test_df')
  expect_identical(reg$con, con)
  expect_equal(reg$n_records, 20L)
  expect_true('unique_id' %in% reg$columns)
  expect_true(reg$needs_cleanup)
})

test_that('register_data handles character table name', {
  con <- test_con()
  on.exit(test_discon(con))

  DBI::dbWriteTable(con, 'src_table', fake_20, overwrite = TRUE)
  reg <- irelink:::register_data('src_table', con = con, tbl_name = '__test_char')
  on.exit(irelink:::drop_registered(con, '__test_char'), add = TRUE, after = FALSE)

  expect_equal(reg$tbl_name, '__test_char')
  expect_equal(reg$n_records, 20L)
  expect_true('unique_id' %in% reg$columns)

  # Can query the view
  result <- DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM __test_char')
  expect_equal(result$n, 20L)
})

test_that('register_data handles tbl_lazy input', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')
  con <- test_con()
  on.exit(test_discon(con))

  DBI::dbWriteTable(con, 'lazy_src', fake_20, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(con, 'lazy_src')

  reg <- irelink:::register_data(tbl_ref, tbl_name = '__test_lazy')
  on.exit(irelink:::drop_registered(con, '__test_lazy'), add = TRUE, after = FALSE)

  expect_equal(reg$tbl_name, '__test_lazy')
  expect_identical(reg$con, con)
  expect_equal(reg$n_records, 20L)
  expect_true('unique_id' %in% reg$columns)
})

test_that('register_data replaces table with view without error', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')
  con <- test_con()
  on.exit(test_discon(con))

  # First create as TABLE (data.frame path)
  reg1 <- irelink:::register_data(fake_20, con = con, tbl_name = '__test_replace')

  # Now create as VIEW (tbl_lazy path) — should not error

  DBI::dbWriteTable(con, 'replace_src', fake_20, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(con, 'replace_src')
  reg2 <- irelink:::register_data(tbl_ref, tbl_name = '__test_replace')

  expect_equal(reg2$n_records, 20L)
  irelink:::drop_registered(con, '__test_replace')
})

test_that('il_model works with tbl_lazy input', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')
  con <- test_con()
  on.exit(test_discon(con))

  DBI::dbWriteTable(con, 'model_src', fake_20, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(con, 'model_src')

  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_block_on(surname)

  model <- il_model(tbl_ref, spec = spec)
  expect_s3_class(model, 'il_model')
  il_cleanup(model)
})

test_that('il_model con=NULL extracted from tbl_lazy', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')
  con <- test_con()
  on.exit(test_discon(con))

  DBI::dbWriteTable(con, 'auto_con_src', fake_20, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(con, 'auto_con_src')

  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_block_on(surname)

  # con not passed — should be extracted from tbl_ref
  model <- il_model(tbl_ref, spec = spec)
  expect_identical(model$con, con)
  il_cleanup(model)
})

test_that('register_data errors on unsupported input', {
  con <- test_con()
  on.exit(test_discon(con))

  expect_error(
    irelink:::register_data(42, con = con),
    'data frame'
  )
})

test_that('register_data errors on zero-row data.frame', {
  con <- test_con()
  on.exit(test_discon(con))

  expect_error(
    irelink:::register_data(data.frame(), con = con),
    'zero-row'
  )
})
