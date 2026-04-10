# Sprint 2 — Level composition: cl_levels(), cl_null(), cl_else(),
# cl_and(), cl_or(), cl_not()
# Translated from: test_comparison_level_composition.py,
# test_compound_comparison_levels.py

# --- cl_null() / cl_else() ------------------------------------------------

test_that('cl_null() creates a null-handling sentinel', {
  lev <- cl_null()
  expect_s3_class(lev, 'il_comparison_level')
  expect_true(lev$is_null_level)
})

test_that('cl_else() creates a catch-all fallback level', {
  lev <- cl_else()
  expect_s3_class(lev, 'il_comparison_level')
  expect_true(lev$is_else_level)
})

# --- cl_levels() ----------------------------------------------------------

test_that('cl_levels() nests child levels in order', {
  lvls <- cl_levels(
    cl_null(),
    cl_exact(),
    cl_jaro_winkler(0.95),
    cl_jaro_winkler(0.88),
    cl_else()
  )
  expect_s3_class(lvls, 'il_comparison_level')
  expect_length(lvls$levels, 5)
})

test_that('cl_levels() accepts term_frequency flag', {
  lvls <- cl_levels(cl_null(), cl_exact(), cl_else(), term_frequency = TRUE)
  expect_true(lvls$term_frequency)
})

test_that('cl_levels() validates cl_null() is first if present', {
  expect_error(
    cl_levels(cl_exact(), cl_null(), cl_else()),
    class = 'il_error_validation'
  )
})

test_that('cl_levels() validates cl_else() is last if present', {
  expect_error(
    cl_levels(cl_null(), cl_else(), cl_exact()),
    class = 'il_error_validation'
  )
})

test_that('cl_levels() works without cl_null() and cl_else()', {
  lvls <- cl_levels(cl_exact(), cl_jaro_winkler(0.9))
  expect_s3_class(lvls, 'il_comparison_level')
  expect_length(lvls$levels, 2)
})

# --- cl_and() / cl_or() / cl_not() ----------------------------------------
# From: test_comparison_level_composition.py

test_that('cl_and/cl_or/cl_not create boolean nodes', {
  and_node <- cl_and(cl_exact(), cl_jaro_winkler(0.9))
  or_node <- cl_or(cl_exact(), cl_jaro_winkler(0.9))
  not_node <- cl_not(cl_exact())

  expect_identical(
    vapply(list(and_node, or_node, not_node), `[[`, character(1), 'method'),
    c('and', 'or', 'not')
  )
})

test_that('cl_and() of two null levels is still a null level', {
  # From: test_null_level_composition
  node <- cl_and(cl_null(), cl_null())
  expect_true(node$is_null_level)
})

test_that('cl_or() of two null levels is still a null level', {
  node <- cl_or(cl_null(), cl_null())
  expect_true(node$is_null_level)
})

test_that('cl_not() of a null level is not a null level', {
  # From: test_not
  node <- cl_not(cl_null())
  expect_false(node$is_null_level)
})

test_that('cl_and() of exact + null is not a null level', {
  node <- cl_and(cl_exact(), cl_null())
  expect_false(node$is_null_level)
})

test_that('cl_and/cl_or/cl_not error with no arguments', {
  expect_error(cl_and())
  expect_error(cl_or())
  expect_error(cl_not())
})

test_that('nested composition: cl_not(cl_or(cl_exact(), cl_exact()))', {
  # From: test_comparison_level_composition.py subtests

  node <- cl_not(cl_or(cl_exact(), cl_exact()))
  expect_s3_class(node, 'il_comparison_level')
  expect_equal(node$method, 'not')
})
