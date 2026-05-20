# Sprint 8 — Deterministic linking: il_deterministic_link()
# Translated from: test_full_example_deterministic_link.py

test_that('il_deterministic_link() returns a tibble of exact-match pairs', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # Create data with known exact duplicates
  df <- data.frame(
    unique_id = 1:6,
    first_name = c('John', 'John', 'Mary', 'Mary', 'Jane', 'Bob'),
    surname = c('Smith', 'Smith', 'Jones', 'Jones', 'Taylor', 'Brown'),
    dob = c(
      '1990-01-01',
      '1990-01-01',
      '1985-05-15',
      '1985-05-15',
      '1992-03-20',
      '1980-12-01'
    )
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  result <- il_deterministic_link(df, spec = spec, con = con)

  expect_s3_class(result, 'tbl_df')
  expect_true(nrow(result) > 0)
  # John Smith should match John Smith
  expect_true(any(
    result$unique_id_l == 1 &
      result$unique_id_r == 2 |
      result$unique_id_l == 2 & result$unique_id_r == 1
  ))
})

test_that('il_deterministic_link() does not require trained parameters', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('Alice', 'Alice', 'Bob', 'Carol'),
    surname = c('Smith', 'Smith', 'Jones', 'Williams')
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  # Should work without any il_estimate_* calls
  result <- il_deterministic_link(df, spec = spec, con = con)
  expect_s3_class(result, 'tbl_df')
})

test_that('il_deterministic_link() rejects unsupported multi-table modes', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:2,
    first_name = c('Alice', 'Alice'),
    surname = c('Smith', 'Smith')
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  expect_error(
    il_deterministic_link(df, df, spec = spec, con = con, link_type = 'link'),
    'single-table'
  )
})
