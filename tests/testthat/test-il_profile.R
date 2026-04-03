# Sprint 5 — Exploration: il_profile()
# Translated from: test_profile_data.py

test_that('il_profile() returns value counts for selected columns', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    id = 1:6,
    name = c('Alice', 'Alice', 'Bob', 'Bob', 'Bob', 'Eve')
  )

  result <- il_profile(df, name, con = con)
  expect_s3_class(result, 'tbl_df')
  expect_true('value' %in% names(result) || 'name' %in% names(result))
})

test_that('il_profile() handles all-null columns gracefully', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    id = 1:3,
    blank = c(NA, NA, NA)
  )

  # From: test_profile_null_columns — warns/handles all-null gracefully
  result <- il_profile(df, blank, con = con)
  expect_s3_class(result, 'tbl_df')
  expect_true(nrow(result) == 0 || all(is.na(result$value)))
})

test_that('il_profile() accepts raw SQL expressions as character strings', {
  skip_if_not_installed('duckdb')

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(
    id = 1:4,
    first_name = c('Alice', 'Alice', 'Bob', 'Bob'),
    city = c('London', 'Paris', 'London', 'Paris')
  )

  result <- il_profile(df, "first_name || ' ' || city", con = con)
  expect_s3_class(result, 'tbl_df')
  expect_true(nrow(result) > 0)
  expect_identical(result$column[[1L]], "first_name || ' ' || city")
})

test_that('il_profile() mixes bare column names and SQL expressions', {
  skip_if_not_installed('duckdb')

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(
    id = 1:4,
    first_name = c('Alice', 'Alice', 'Bob', 'Bob'),
    city = c('London', 'Paris', 'London', 'Paris')
  )

  result <- il_profile(df, first_name, 'city || first_name', con = con)
  expect_identical(sort(unique(result$column)), sort(c('first_name', 'city || first_name')))
})

test_that('il_profile() works with multiple columns', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    id = 1:4,
    first_name = c('Alice', 'Alice', 'Bob', 'Eve'),
    surname = c('Smith', 'Jones', 'Smith', 'Smith')
  )

  result <- il_profile(df, first_name, surname, con = con)
  expect_s3_class(result, 'tbl_df')
  expect_true(nrow(result) > 0)
})
