# Sprint 5 — Exploration: il_profile()
# Translated from: test_profile_data.py

test_that("il_profile() returns value counts for selected columns", {
  skip_if_sprint_lt(5)
  skip_if_not_installed("RSQLite")

  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))

  df <- data.frame(
    id = 1:6,
    name = c("Alice", "Alice", "Bob", "Bob", "Bob", "Eve")
  )

  result <- il_profile(df, name, con = con)
  expect_s3_class(result, "tbl_df")
  expect_true("value" %in% names(result) || "name" %in% names(result))
})

test_that("il_profile() handles all-null columns gracefully", {
  skip_if_sprint_lt(5)
  skip_if_not_installed("RSQLite")

  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))

  df <- data.frame(
    id = 1:3,
    blank = c(NA, NA, NA)
  )

  # From: test_profile_null_columns — warns/handles all-null gracefully
  result <- il_profile(df, blank, con = con)
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) == 0 || all(is.na(result$value)))
})

test_that("il_profile() works with multiple columns", {
  skip_if_sprint_lt(5)
  skip_if_not_installed("RSQLite")

  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))

  df <- data.frame(
    id = 1:4,
    first_name = c("Alice", "Alice", "Bob", "Eve"),
    surname = c("Smith", "Jones", "Smith", "Smith")
  )

  result <- il_profile(df, first_name, surname, con = con)
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
})
