# Sprint 3 — Blocking rules: il_block_on() and block_on()
# Translated from: test_blocking.py (blocking rule basics),
# test_blocking_rule_composition.py (AND/OR/NOT)

# --- il_block_on() --------------------------------------------------------

test_that('il_block_on() takes an il_spec and returns an il_spec', {
  spec <- il_spec() |> il_block_on(first_name)
  expect_s3_class(spec, 'il_spec')
})

test_that('il_block_on() adds blocking rules to the spec', {
  spec <- il_spec() |>
    il_block_on(first_name) |>
    il_block_on(surname)

  expect_length(spec$blocking_rules, 2)
})

test_that('multiple il_block_on() calls accumulate with OR semantics', {
  spec <- il_spec() |>
    il_block_on(first_name) |>
    il_block_on(surname) |>
    il_block_on(dob)

  # Three separate blocking rules, OR-ed together
  expect_length(spec$blocking_rules, 3)
})

test_that('il_block_on() with multiple columns creates AND within a rule', {
  # block_on(first_name, surname) means first_name AND surname must match
  spec <- il_spec() |> il_block_on(first_name, surname)

  expect_length(spec$blocking_rules, 1)
  # The single rule should reference both columns
})

test_that('passing a non-spec to il_block_on() errors', {
  expect_error(
    il_block_on('not a spec', first_name),
    class = 'il_error_type'
  )
})

test_that('il_block_on() requires at least one column or where condition', {
  expect_error(
    il_block_on(il_spec()),
    'requires at least one column'
  )
})

test_that('print.il_spec() shows blocking rules', {
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(
      .where = 'l.given_name = r.surname AND l.surname = r.given_name'
    ) |>
    il_block_on(surname)

  expect_output(print(spec), 'first_name')
  expect_output(print(spec), 'surname')
  expect_output(
    print(spec),
    'WHERE l.given_name = r.surname AND l.surname = r.given_name',
    fixed = TRUE
  )
})

# --- block_on() (standalone) ----------------------------------------------
# From: test_blocking.py — standalone rules for training

test_that('block_on() creates a standalone blocking rule without a spec', {
  rule <- block_on(first_name, surname)
  # Should NOT be an il_spec; should be a blocking rule object
  expect_false(is_il_spec(rule))
})

test_that('block_on() with a single column works', {
  rule <- block_on(first_name)
  expect_true(!is.null(rule))
})

test_that('block_on() with multiple columns creates an AND rule', {
  # From: test_blocking_rule_composition.py — AND of columns
  rule <- block_on(first_name, surname, dob)
  expect_true(!is.null(rule))
})

# --- Formula syntax (col ~ transform) ------------------------------------

test_that('il_block_on() accepts formula syntax for per-column transforms', {
  spec <- il_spec() |>
    il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
  expect_s3_class(spec, 'il_spec')
  expect_length(spec$blocking_rules, 1)
  rule <- spec$blocking_rules[[1]]
  expect_equal(rule$columns, c('first_name', 'surname'))
  expect_true(is.list(rule$transform))
  expect_s3_class(rule$transform[['first_name']], 'il_column_transform')
  expect_s3_class(rule$transform[['surname']], 'il_column_transform')
})

test_that('il_block_on() mixes bare columns and formula transforms', {
  spec <- il_spec() |>
    il_block_on(postcode_fake ~ il_substr(1, 3), dob)
  rule <- spec$blocking_rules[[1]]
  expect_equal(rule$columns, c('postcode_fake', 'dob'))
  expect_s3_class(rule$transform[['postcode_fake']], 'il_column_transform')
  expect_null(rule$transform[['dob']])
})

test_that('block_on() accepts formula syntax', {
  rule <- block_on(first_name ~ il_substr(1, 2), surname ~ il_substr(1, 2))
  expect_s3_class(rule, 'il_blocking_rule')
  expect_true(is.list(rule$transform))
})

test_that('il_block_on() errors on one-sided formula', {
  expect_snapshot(
    error = TRUE,
    il_block_on(il_spec(), ~ il_substr(1, 3))
  )
})

test_that('il_block_on() errors on non-symbol LHS in formula', {
  expect_snapshot(
    error = TRUE,
    il_block_on(il_spec(), 'first_name' ~ il_substr(1, 3))
  )
})

test_that('il_block_on() errors when formula RHS is not a function', {
  expect_snapshot(
    error = TRUE,
    il_block_on(il_spec(), first_name ~ 'not_a_transform')
  )
})

test_that('formula transforms generate correct SQL', {
  spec <- il_spec() |>
    il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
  rule <- spec$blocking_rules[[1]]
  sql <- build_blocking_condition(
    rule$columns,
    transform = rule$transform,
    dialect = 'duckdb'
  )
  expect_match(sql, 'SUBSTRING(l.first_name, 1, 3)', fixed = TRUE)
  expect_match(sql, 'SUBSTRING(r.first_name, 1, 3)', fixed = TRUE)
  expect_match(sql, 'SUBSTRING(l.surname, 1, 4)', fixed = TRUE)
  expect_match(sql, 'SUBSTRING(r.surname, 1, 4)', fixed = TRUE)
})

test_that('mixed formula+bare generates correct SQL', {
  spec <- il_spec() |>
    il_block_on(postcode_fake ~ il_substr(1, 3), dob)
  rule <- spec$blocking_rules[[1]]
  sql <- build_blocking_condition(
    rule$columns,
    transform = rule$transform,
    dialect = 'duckdb'
  )
  expect_match(sql, 'SUBSTRING(l.postcode_fake, 1, 3)', fixed = TRUE)
  expect_match(sql, 'l.dob = r.dob', fixed = TRUE)
})

test_that('print.il_spec shows per-column formula transforms', {
  spec <- il_spec() |>
    il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
  expect_output(print(spec), 'il_substr(1,3)', fixed = TRUE)
  expect_output(print(spec), 'il_substr(1,4)', fixed = TRUE)
})

# --- .transform named list (programmatic API) --------------------------------

test_that('il_block_on() accepts a named list .transform', {
  spec <- il_spec() |>
    il_block_on(
      first_name, surname,
      .transform = list(first_name = il_substr(1, 3), surname = il_substr(1, 4))
    )
  expect_s3_class(spec, 'il_spec')
  expect_length(spec$blocking_rules, 1)
  expect_true(is.list(spec$blocking_rules[[1]]$transform))
})

test_that('named list .transform must match blocking columns', {
  expect_error(
    il_block_on(
      il_spec(),
      first_name,
      .transform = list(first_name = tolower, surname = toupper)
    ),
    class = 'il_error_type'
  )
  expect_error(
    il_block_on(
      il_spec(),
      first_name, surname,
      .transform = list(first_name = tolower)
    ),
    class = 'il_error_type'
  )
})

test_that('formula transforms can fill named list .transform entries', {
  spec <- il_spec() |>
    il_block_on(
      first_name ~ il_substr(1, 3),
      surname,
      .transform = list(surname = tolower)
    )
  rule <- spec$blocking_rules[[1]]
  expect_s3_class(rule$transform$first_name, 'il_column_transform')
  expect_identical(rule$transform$surname, tolower)
})

test_that('il_block_on() errors on unnamed list .transform', {
  expect_snapshot(
    error = TRUE,
    il_block_on(il_spec(), first_name, .transform = list(il_substr(1, 3)))
  )
})

test_that('il_block_on() errors on list with non-function entries', {
  expect_snapshot(
    error = TRUE,
    il_block_on(il_spec(), first_name, .transform = list(first_name = 'not_a_function'))
  )
})

# --- Full spec composition: compare + block --------------------------------

test_that('a complete spec can be built with pipes', {
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_date_diff(days(30), days(365))) |>
    il_compare(city, cl_exact()) |>
    il_compare(email, cl_email()) |>
    il_block_on(first_name) |>
    il_block_on(surname)

  expect_s3_class(spec, 'il_spec')
  expect_length(spec$comparisons, 5)
  expect_length(spec$blocking_rules, 2)
})
