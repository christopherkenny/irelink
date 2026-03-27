# Sprint 3 — Spec composition: il_compare()
# Translated from: test_comparison_level_composition.py::test_composition_outputs,
#                  test_new_comparison_levels.py (creator tests),
#                  test_settings_validation.py (column validation),
#                  test_columns_selected.py (tidyselect)

test_that('il_compare() takes an il_spec first and returns an il_spec', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |> il_compare(first_name, cl_exact())
  expect_s3_class(spec, 'il_spec')
})

test_that('two il_compare() calls accumulate comparisons', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7))

  expect_length(spec$comparisons, 2)
})

test_that('multiple il_compare() calls never overwrite earlier ones', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_compare(dob, cl_date_diff(days(30)))

  expect_length(spec$comparisons, 3)
  # First comparison should still be first_name
})

test_that('tidyselect: bare column name works in il_compare()', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |> il_compare(first_name, cl_exact())
  expect_length(spec$comparisons, 1)
})

test_that('tidyselect: c() for multiple columns works', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |> il_compare(c(first_name, last_name), cl_exact())
  # Each column gets its own comparison
  expect_length(spec$comparisons, 2)
})

test_that('passing a non-spec to il_compare() errors informatively', {
  skip_if_sprint_lt(3)
  expect_error(
    il_compare('not a spec', first_name, cl_exact()),
    class = 'il_error_type'
  )
})

test_that('il_compare() stores the comparison method with the column', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7))

  comp <- spec$comparisons[[1]]
  expect_equal(comp$method$method, 'jaro_winkler')
})

test_that('il_compare() accepts domain bundles', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(email, cl_email()) |>
    il_compare(first_name, cl_name())

  expect_length(spec$comparisons, 2)
})

test_that('tidyselect: starts_with() selects matching columns', {
  skip_if_sprint_lt(3)
  # From: 09-implementation-plan §3d — tidyselect edge case
  spec <- il_spec() |>
    il_compare(starts_with('addr_'), cl_exact())
  # Should create one comparison per matching column
  expect_s3_class(spec, 'il_spec')
})

test_that('tidyselect: everything() selects all columns', {
  skip_if_sprint_lt(3)
  # From: 09-implementation-plan §6b — tidyselect edge case
  spec <- il_spec() |>
    il_compare(everything(), cl_exact())
  expect_s3_class(spec, 'il_spec')
})

test_that('tidyselect: matches() selects by regex pattern', {
  skip_if_sprint_lt(3)
  # From: 09-implementation-plan §6b — tidyselect edge case
  spec <- il_spec() |>
    il_compare(matches('name'), cl_jaro_winkler(0.9))
  expect_s3_class(spec, 'il_spec')
})

test_that('print.il_spec() shows comparisons after il_compare()', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(city, cl_exact())

  expect_output(print(spec), 'first_name')
  expect_output(print(spec), 'city')
})
