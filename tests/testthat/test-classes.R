# Sprint 1 — Internal S3 class constructors and validators
# Tests the low-level constructor/validator contract for il_spec,
# il_model, and il_compared.

test_that('new_il_spec() creates a valid il_spec structure', {
  skip_if_sprint_lt(1)
  spec <- new_il_spec()
  expect_s3_class(spec, 'il_spec')
  expect_type(spec$comparisons, 'list')
  expect_type(spec$blocking_rules, 'list')
})

test_that('validate_il_spec() accepts well-formed specs', {
  skip_if_sprint_lt(1)
  spec <- new_il_spec()
  expect_silent(validate_il_spec(spec))
})

test_that('validate_il_spec() rejects malformed objects', {
  skip_if_sprint_lt(1)
  # Missing class
  bad <- list(comparisons = list(), blocking_rules = list())
  expect_error(validate_il_spec(bad))

  # Missing required component
  bad2 <- structure(list(blocking_rules = list()), class = 'il_spec')
  expect_error(validate_il_spec(bad2))
})

test_that('new_il_model() creates a valid il_model structure', {
  skip_if_sprint_lt(1)
  model <- new_il_model()
  expect_s3_class(model, 'il_model')
})

test_that('validate_il_model() rejects malformed objects', {
  skip_if_sprint_lt(1)
  bad <- list(spec = NULL)
  expect_error(validate_il_model(bad))
})

test_that('new_il_compared() creates a valid il_compared structure', {
  skip_if_sprint_lt(1)
  cmp <- new_il_compared()
  expect_s3_class(cmp, 'il_compared')
  # il_compared is a tibble subclass
  expect_s3_class(cmp, 'tbl_df')
})

test_that('validate_il_compared() rejects malformed objects', {
  skip_if_sprint_lt(1)
  bad <- data.frame(x = 1)
  expect_error(validate_il_compared(bad))
})
