# Sprint 1 — Unit helper constructors: days(), months(), years(), km(), mi()
# No direct splink equivalent — these are irelink-specific tagged-value
# constructors inspired by gt's px()/pct() pattern.

test_that('days() creates a tagged value with correct class and value', {
  d <- days(30)
  expect_s3_class(d, 'il_days')
  expect_equal(d$value, 30)
})

test_that('months() creates a tagged value with correct class and value', {
  m <- months(6)
  expect_s3_class(m, 'il_months')
  expect_equal(m$value, 6)
})

test_that('years() creates a tagged value with correct class and value', {
  y <- years(10)
  expect_s3_class(y, 'il_years')
  expect_equal(y$value, 10)
})

test_that('km() creates a tagged value with correct class and value', {
  k <- km(5)
  expect_s3_class(k, 'il_km')
  expect_equal(k$value, 5)
})

test_that('mi() creates a tagged value with correct class and value', {
  m <- mi(10)
  expect_s3_class(m, 'il_mi')
  expect_equal(m$value, 10)
})

test_that('unit helpers reject non-numeric input', {
  expect_error(days('thirty'))
  expect_error(km(NULL))
  expect_error(mi(TRUE))
})

test_that('unit helpers reject negative values', {
  expect_error(days(-1))
  expect_error(km(-5))
})

test_that('unit helpers print informatively', {
  expect_output(print(days(30)), '30')
  expect_output(print(km(5)), '5')
})
