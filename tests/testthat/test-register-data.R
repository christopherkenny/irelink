# Tests for register_data() — database connection support

test_that('register_data handles data.frame input', {
  con <- test_con()
  on.exit(test_discon(con))

  reg <- register_data(fake_20, con = con, tbl_name = '__test_df')
  on.exit(drop_registered(con, '__test_df'), add = TRUE, after = FALSE)

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
  reg <- register_data('src_table', con = con, tbl_name = '__test_char')
  on.exit(drop_registered(con, '__test_char'), add = TRUE, after = FALSE)

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

  reg <- register_data(tbl_ref, tbl_name = '__test_lazy')
  on.exit(drop_registered(con, '__test_lazy'), add = TRUE, after = FALSE)

  expect_equal(reg$tbl_name, '__test_lazy')
  expect_identical(reg$con, con)
  expect_equal(reg$n_records, 20L)
  expect_true('unique_id' %in% reg$columns)
})

test_that('register_data handles reserved-word source table names', {
  con <- test_con()
  on.exit(test_discon(con))

  DBI::dbWriteTable(con, 'select', fake_20, overwrite = TRUE)
  reg <- register_data('select', con = con, tbl_name = '__test_reserved')
  on.exit(drop_registered(con, '__test_reserved'), add = TRUE, after = FALSE)

  expect_equal(reg$n_records, 20L)
  expect_equal(
    DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM "__test_reserved"')$n,
    20L
  )
})

test_that('register_data handles tbl_lazy input on SQLite', {
  skip_if_not_installed('RSQLite')
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')

  con <- DBI::dbConnect(RSQLite::SQLite(), ':memory:')
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbWriteTable(con, 'lazy_src_sqlite', fake_20, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(con, 'lazy_src_sqlite')

  reg <- register_data(tbl_ref, tbl_name = '__test_lazy_sqlite')
  on.exit(drop_registered(con, '__test_lazy_sqlite'), add = TRUE, after = FALSE)

  expect_equal(reg$n_records, 20L)
  expect_equal(
    DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM "__test_lazy_sqlite"')$n,
    20L
  )
})

test_that('register_data materializes stable synthetic unique_id values', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')
  con <- test_con()
  on.exit(test_discon(con))

  src <- fake_20[, c('first_name', 'surname')]
  DBI::dbWriteTable(con, 'lazy_random_src', src, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(
    con,
    dbplyr::sql(
      'SELECT first_name, surname FROM lazy_random_src ORDER BY random()'
    )
  )

  reg <- register_data(tbl_ref, tbl_name = '__test_lazy_random')
  on.exit(drop_registered(con, '__test_lazy_random'), add = TRUE, after = FALSE)

  first_read <- DBI::dbGetQuery(
    con,
    paste(
      'SELECT unique_id, first_name, surname',
      'FROM __test_lazy_random ORDER BY unique_id'
    )
  )
  second_read <- DBI::dbGetQuery(
    con,
    paste(
      'SELECT unique_id, first_name, surname',
      'FROM __test_lazy_random ORDER BY unique_id'
    )
  )

  expect_identical(first_read, second_read)
})

test_that('register_data replaces table with view without error', {
  skip_if_not_installed('dbplyr')
  skip_if_not_installed('dplyr')
  con <- test_con()
  on.exit(test_discon(con))

  # First create as TABLE (data.frame path)
  reg1 <- register_data(fake_20, con = con, tbl_name = '__test_replace')

  # Now create as VIEW (tbl_lazy path) — should not error

  DBI::dbWriteTable(con, 'replace_src', fake_20, overwrite = TRUE)
  tbl_ref <- dplyr::tbl(con, 'replace_src')
  reg2 <- register_data(tbl_ref, tbl_name = '__test_replace')

  expect_equal(reg2$n_records, 20L)
  drop_registered(con, '__test_replace')
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
    register_data(42, con = con),
    'data frame'
  )
})

test_that('register_data errors on zero-row data.frame', {
  con <- test_con()
  on.exit(test_discon(con))

  expect_error(
    register_data(data.frame(), con = con),
    'zero-row'
  )
})

test_that('register_data rejects duplicate unique_id values', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = c(1L, 1L, 2L),
    first_name = c('A', 'B', 'C')
  )

  expect_error(
    register_data(df, con = con),
    'uniquely identify'
  )
})

test_that('register_data rejects missing unique_id values', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = c(1L, NA_integer_, 2L),
    first_name = c('A', 'B', 'C')
  )

  expect_error(
    register_data(df, con = con),
    'missing values'
  )
})
