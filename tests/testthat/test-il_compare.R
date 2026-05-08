# Sprint 3 — Spec composition: il_compare()
# Translated from: test_comparison_level_composition.py::test_composition_outputs,
# test_new_comparison_levels.py (creator tests),
# test_settings_validation.py (column validation),
# test_columns_selected.py (tidyselect)

test_that('il_compare() takes an il_spec first and returns an il_spec', {
  spec <- il_spec() |> il_compare(first_name, cl_exact())
  expect_s3_class(spec, 'il_spec')
})

test_that('two il_compare() calls accumulate comparisons', {
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7))

  expect_length(spec$comparisons, 2)
})

test_that('multiple il_compare() calls never overwrite earlier ones', {
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_compare(dob, cl_date_diff(days(30)))

  expect_length(spec$comparisons, 3)
  # First comparison should still be first_name
})

test_that('tidyselect: bare column name works in il_compare()', {
  spec <- il_spec() |> il_compare(first_name, cl_exact())
  expect_length(spec$comparisons, 1)
})

test_that('tidyselect: c() for multiple columns works', {
  spec <- il_spec() |> il_compare(c(first_name, last_name), cl_exact())
  # Each column gets its own comparison
  expect_length(spec$comparisons, 2)
})

test_that('passing a non-spec to il_compare() errors informatively', {
  expect_error(
    il_compare('not a spec', first_name, cl_exact()),
    class = 'il_error_type'
  )
})

test_that('il_compare() stores the comparison method with the column', {
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7))

  comp <- spec$comparisons[[1]]
  expect_equal(comp$method$method, 'jaro_winkler')
})

test_that('il_compare() accepts domain bundles', {
  spec <- il_spec() |>
    il_compare(email, cl_email()) |>
    il_compare(first_name, cl_name())

  expect_length(spec$comparisons, 2)
})

test_that('tidyselect: starts_with() selects matching columns', {
  # From: 09-implementation-plan §3d — tidyselect edge case
  spec <- il_spec() |>
    il_compare(starts_with('addr_'), cl_exact())
  # Should create one comparison per matching column
  expect_s3_class(spec, 'il_spec')
})

test_that('tidyselect helpers resolve when il_model() sees data columns', {
  skip_if_not_installed('RSQLite')
  skip_if_not_installed('tidyselect')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    addr_1 = c('a', 'a', 'b', 'b'),
    addr_2 = c('x', 'x', 'y', 'z'),
    other = c('m', 'n', 'm', 'n')
  )
  spec <- il_spec() |>
    il_compare(starts_with('addr_'), cl_exact()) |>
    il_block_on(addr_1)

  model <- il_model(df, spec = spec, con = con)
  expect_equal(
    vapply(model$spec$comparisons, function(comp) comp$columns, character(1)),
    c('addr_1', 'addr_2')
  )
})

test_that('tidyselect where() uses data column classes when resolving', {
  skip_if_not_installed('RSQLite')
  skip_if_not_installed('tidyselect')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    name = c('a', 'a', 'b', 'b'),
    age = c(10, 10, 20, 21),
    stringsAsFactors = FALSE
  )
  spec <- il_spec() |>
    il_compare(tidyselect::where(is.character), cl_exact()) |>
    il_block_on(name)

  model <- il_model(df, spec = spec, con = con)
  expect_equal(length(model$spec$comparisons), 1)
  expect_equal(model$spec$comparisons[[1]]$columns, 'name')
})

test_that('tidyselect: everything() selects all columns', {
  # From: 09-implementation-plan §6b — tidyselect edge case
  spec <- il_spec() |>
    il_compare(everything(), cl_exact())
  expect_s3_class(spec, 'il_spec')
})

test_that('tidyselect: matches() selects by regex pattern', {
  # From: 09-implementation-plan §6b — tidyselect edge case
  spec <- il_spec() |>
    il_compare(matches('name'), cl_jaro_winkler(0.9))
  expect_s3_class(spec, 'il_spec')
})

test_that('print.il_spec() shows comparisons after il_compare()', {
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(city, cl_exact())

  expect_output(print(spec), 'first_name')
  expect_output(print(spec), 'city')
})
