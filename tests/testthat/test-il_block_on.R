# Sprint 3 — Blocking rules: il_block_on() and block_on()
# Translated from: test_blocking.py (blocking rule basics),
#                  test_blocking_rule_composition.py (AND/OR/NOT)

# --- il_block_on() --------------------------------------------------------

test_that('il_block_on() takes an il_spec and returns an il_spec', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |> il_block_on(first_name)
  expect_s3_class(spec, 'il_spec')
})

test_that('il_block_on() adds blocking rules to the spec', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_block_on(first_name) |>
    il_block_on(surname)

  expect_length(spec$blocking_rules, 2)
})

test_that('multiple il_block_on() calls accumulate with OR semantics', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_block_on(first_name) |>
    il_block_on(surname) |>
    il_block_on(dob)

  # Three separate blocking rules, OR-ed together
  expect_length(spec$blocking_rules, 3)
})

test_that('il_block_on() with multiple columns creates AND within a rule', {
  skip_if_sprint_lt(3)
  # block_on(first_name, surname) means first_name AND surname must match
  spec <- il_spec() |> il_block_on(first_name, surname)

  expect_length(spec$blocking_rules, 1)
  # The single rule should reference both columns
})

test_that('passing a non-spec to il_block_on() errors', {
  skip_if_sprint_lt(3)
  expect_error(
    il_block_on('not a spec', first_name),
    class = 'il_error_type'
  )
})

test_that('print.il_spec() shows blocking rules', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(surname)

  expect_output(print(spec), 'first_name')
  expect_output(print(spec), 'surname')
})

# --- block_on() (standalone) ----------------------------------------------
# From: test_blocking.py — standalone rules for training

test_that('block_on() creates a standalone blocking rule without a spec', {
  skip_if_sprint_lt(3)
  rule <- block_on(first_name, surname)
  # Should NOT be an il_spec; should be a blocking rule object
  expect_false(is_il_spec(rule))
})

test_that('block_on() with a single column works', {
  skip_if_sprint_lt(3)
  rule <- block_on(first_name)
  expect_true(!is.null(rule))
})

test_that('block_on() with multiple columns creates an AND rule', {
  skip_if_sprint_lt(3)
  # From: test_blocking_rule_composition.py — AND of columns
  rule <- block_on(first_name, surname, dob)
  expect_true(!is.null(rule))
})

# --- Full spec composition: compare + block --------------------------------

test_that('a complete spec can be built with pipes', {
  skip_if_sprint_lt(3)
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
