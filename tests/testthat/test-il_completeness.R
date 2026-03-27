# Sprint 5 — Exploration: il_completeness()
# Translated from: test_completeness.py

test_that("il_completeness() returns a tibble with one row per column", {
  skip_if_sprint_lt(5)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    id = 1:5,
    name = c("Alice", "Bob", NA, "Diana", "Eve"),
    city = c("London", NA, NA, "Paris", "Berlin")
  )

  result <- il_completeness(df, con = con)

  expect_s3_class(result, "tbl_df")
  expect_true("column" %in% names(result))
  expect_true("pct_non_null" %in% names(result))
})

test_that("il_completeness() computes correct non-null percentages", {
  skip_if_sprint_lt(5)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    id = 1:4,
    a = c("x", "y", NA, "z"),   # 75% non-null
    b = c(NA, NA, NA, NA)         # 0% non-null
  )

  result <- il_completeness(df, con = con)

  a_row <- result[result$column == "a", ]
  b_row <- result[result$column == "b", ]

  expect_equal(a_row$pct_non_null, 75, tolerance = 0.01)
  expect_equal(b_row$pct_non_null, 0, tolerance = 0.01)
})

test_that("il_completeness() handles a fully-complete dataset", {
  skip_if_sprint_lt(5)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(id = 1:10, name = letters[1:10])
  result <- il_completeness(df, con = con)

  name_row <- result[result$column == "name", ]
  expect_equal(name_row$pct_non_null, 100, tolerance = 0.01)
})
