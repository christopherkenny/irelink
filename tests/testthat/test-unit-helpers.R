# Unit helper constructors: days(), months(), years(), km(), mi()

test_that('unit helpers create tagged values with correct class and value', {
  objs <- list(days(30), months(6), years(10), km(5), mi(10))
  expected_classes <- c('il_days', 'il_months', 'il_years', 'il_km', 'il_mi')
  expected_values <- c(30, 6, 10, 5, 10)

  actual_classes <- vapply(objs, function(o) class(o)[1], character(1))
  actual_values <- vapply(objs, function(o) o$value, numeric(1))

  expect_identical(actual_classes, expected_classes)
  expect_equal(actual_values, expected_values)
  expect_equal(days(0)$value, 0)
})

test_that('unit helpers reject invalid input', {
  expect_error(days('thirty'))
  expect_error(km(NULL))
  expect_error(mi(TRUE))
  expect_error(days(-1))
  expect_error(km(-5))
  expect_error(days(NA))
  expect_error(km(NA_real_))
  expect_error(days(c(1, 2)))
  expect_error(km(c(5, 10)))
  expect_error(days(Inf))
  expect_error(km(NaN))
})
