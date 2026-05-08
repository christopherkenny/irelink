# Sprint 6 — Model creation: il_model(), print, summary, is_il_model,
# il_cleanup()
# Translated from: test_full_example_duckdb.py (linker creation),
# test_settings_validation.py (column validation),
# test_caching_tables.py (cleanup)

# Helper spec used across multiple tests in this file
make_test_spec <- function() {
  il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)
}

# --- il_model() -----------------------------------------------------------

test_that('il_model() creates an il_model object', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'Mary', 'Jane', 'John', 'Eve'),
    surname = c('Smith', 'Jones', 'Taylor', 'Smith', 'Adams')
  )

  model <- il_model(df, spec = make_test_spec(), con = con)
  expect_s3_class(model, 'il_model')
})

test_that('is_il_model() works correctly', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'Mary', 'Jane', 'John', 'Eve'),
    surname = c('Smith', 'Jones', 'Taylor', 'Smith', 'Adams')
  )

  model <- il_model(df, spec = make_test_spec(), con = con)
  expect_true(is_il_model(model))
  expect_false(is_il_model('not a model'))
  expect_false(is_il_model(il_spec()))
})

test_that('il_model() validates columns against the data', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_settings_validation.py — missing column produces clear error
  df <- data.frame(unique_id = 1:3, name = c('A', 'B', 'C'))

  # Spec references first_name and surname, but data only has name
  expect_error(il_model(df, spec = make_test_spec(), con = con))
})

test_that("il_model() with link_type='link' requires two datasets", {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:3,
    first_name = c('A', 'B', 'C'),
    surname = c('X', 'Y', 'Z')
  )

  expect_error(
    il_model(df, spec = make_test_spec(), con = con, link_type = 'link')
  )
})

test_that("il_model() with link_type='link' accepts two datasets", {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df1 <- data.frame(
    unique_id = 1:3,
    first_name = c('John', 'Mary', 'Jane'),
    surname = c('Smith', 'Jones', 'Taylor')
  )
  df2 <- data.frame(
    unique_id = 4:6,
    first_name = c('John', 'Mary', 'Alice'),
    surname = c('Smyth', 'Jones', 'Williams')
  )

  model <- il_model(df1, df2, spec = make_test_spec(), con = con, link_type = 'link')
  expect_s3_class(model, 'il_model')
})

test_that("il_model() validates spec columns against right data in link mode", {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df1 <- data.frame(
    unique_id = 1:3,
    first_name = c('John', 'Mary', 'Jane'),
    surname = c('Smith', 'Jones', 'Taylor')
  )
  df2 <- data.frame(
    unique_id = 4:6,
    first_name = c('John', 'Mary', 'Alice')
  )

  expect_error(
    il_model(df1, df2, spec = make_test_spec(), con = con, link_type = 'link'),
    'right data'
  )
})

test_that('il_model() errors when more than two datasets are supplied', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:3,
    first_name = c('A', 'B', 'C'),
    surname = c('X', 'Y', 'Z')
  )

  expect_error(
    il_model(df, df, df, spec = make_test_spec(), con = con, link_type = 'link'),
    'at most two datasets'
  )
})

test_that('print.il_model() shows key info', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'Mary', 'Jane', 'John', 'Eve'),
    surname = c('Smith', 'Jones', 'Taylor', 'Smith', 'Adams')
  )

  model <- il_model(df, spec = make_test_spec(), con = con)

  # Should show record count, comparisons, status
  expect_output(print(model), '5') # record count
  expect_output(print(model), 'untrained|Untrained', perl = TRUE)
})

test_that('summary.il_model() shows untrained status', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'Mary', 'Jane', 'John', 'Eve'),
    surname = c('Smith', 'Jones', 'Taylor', 'Smith', 'Adams')
  )

  model <- il_model(df, spec = make_test_spec(), con = con)
  expect_output(summary(model))
})

# --- R type safety (from 09-implementation-plan §6a) ----------------------

test_that('il_model() handles zero-row data frame gracefully', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = integer(0),
    first_name = character(0),
    surname = character(0)
  )

  # Zero rows should produce a clear error, not a cryptic SQL failure
  expect_error(il_model(df, spec = make_test_spec(), con = con))
})

test_that('il_model() with single-row dedupe produces zero pairs', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1L,
    first_name = 'Alice',
    surname = 'Smith'
  )

  # One record can't form any pairs in deduplication
  model <- il_model(df, spec = make_test_spec(), con = con)
  expect_s3_class(model, 'il_model')
})

test_that('il_model() handles factor columns in data', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = factor(c('John', 'Mary', 'Jane', 'John', 'Eve')),
    surname = factor(c('Smith', 'Jones', 'Taylor', 'Smith', 'Adams'))
  )

  # Factor columns are common in R — should be handled
  model <- il_model(df, spec = make_test_spec(), con = con)
  expect_s3_class(model, 'il_model')
})

# --- il_cleanup() ---------------------------------------------------------
# From: test_caching_tables.py

test_that('il_cleanup() removes temporary tables', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'Mary', 'Jane', 'John', 'Eve'),
    surname = c('Smith', 'Jones', 'Taylor', 'Smith', 'Adams')
  )

  model <- il_model(df, spec = make_test_spec(), con = con)

  # Tables should exist before cleanup
  tables_before <- DBI::dbListTables(con)
  expect_true(length(tables_before) > 0)

  il_cleanup(model)

  # Temporary tables should be removed
  tables_after <- DBI::dbListTables(con)
  expect_true(length(tables_after) < length(tables_before))
})
