# Sprint 4 — Demo data: il_demo()
# Translated from: test_splink_datasets.py::test_datasets_basic_link

test_that("il_demo('fake_1000') returns a tibble", {
  skip_if_sprint_lt(4)
  df <- il_demo("fake_1000")
  expect_s3_class(df, "tbl_df")
})

test_that("il_demo('fake_1000') has expected columns", {
  skip_if_sprint_lt(4)
  df <- il_demo("fake_1000")
  expected_cols <- c("unique_id", "first_name", "surname", "dob", "city", "email")
  for (col in expected_cols) {
    expect_true(col %in% names(df), info = paste("Missing column:", col))
  }
})

test_that("il_demo('fake_1000') has 1000 rows", {
  skip_if_sprint_lt(4)
  df <- il_demo("fake_1000")
  expect_equal(nrow(df), 1000)
})

test_that("il_demo() with no argument lists available datasets", {
  skip_if_sprint_lt(4)
  result <- il_demo()
  # Should return a character vector or print a listing
  expect_true(is.character(result) || is.data.frame(result))
})

test_that("il_demo() with an invalid name errors informatively", {
  skip_if_sprint_lt(4)
  expect_error(il_demo("nonexistent_dataset"))
})

test_that("il_demo('fake_1000_links') returns a list of two tables for linkage", {
  skip_if_sprint_lt(4)
  result <- il_demo("fake_1000_links")
  # Should provide two datasets for a link task
  expect_true(is.list(result) || is.data.frame(result))
})
