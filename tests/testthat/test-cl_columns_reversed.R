# Tests for cl_columns_reversed()

test_that('cl_columns_reversed() creates a custom comparison level', {
  lvl <- cl_columns_reversed('surname')
  expect_s3_class(lvl, 'il_comparison_level')
  expect_equal(lvl$method, 'custom')
  expect_true(grepl('r.surname', lvl$sql_expr))
})

test_that('cl_columns_reversed() one-direction SQL is correct', {
  lvl <- cl_columns_reversed('last_name', symmetrical = FALSE)
  expect_equal(lvl$sql_expr, 'l.{col} = r.last_name')
})

test_that('cl_columns_reversed() symmetrical SQL is correct', {
  lvl <- cl_columns_reversed('last_name', symmetrical = TRUE)
  expect_equal(
    lvl$sql_expr,
    'l.{col} = r.last_name AND l.last_name = r.{col}'
  )
})

test_that('cl_columns_reversed() validates inputs', {
  expect_error(cl_columns_reversed(123), 'single character')
  expect_error(cl_columns_reversed(c('a', 'b')), 'single character')
  expect_error(cl_columns_reversed('x', symmetrical = 'yes'), 'single logical')
})

test_that('cl_columns_reversed() works inside cl_levels()', {
  lvl <- cl_levels(
    cl_null(),
    cl_exact(),
    cl_columns_reversed('surname', symmetrical = TRUE),
    cl_else()
  )
  expect_s3_class(lvl, 'il_comparison_level')
  expect_equal(lvl$method, 'levels')
  expect_length(lvl$levels, 4)
})

test_that('cl_forename_surname() uses cl_columns_reversed() internally', {
  lvl <- cl_forename_surname('last_name')
  # Third level (index 3) should be the swap detection
  swap <- lvl$levels[[3]]
  expect_s3_class(swap, 'il_comparison_level')
  expect_equal(swap$method, 'custom')
  expect_true(grepl('last_name', swap$sql_expr))
})

test_that('cl_columns_reversed() works end-to-end in model', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('John', 'Smith', 'Jane', 'Jane'),
    last_name = c('Smith', 'John', 'Doe', 'Doe'),
    stringsAsFactors = FALSE
  )

  spec <- il_spec() |>
    il_compare(
      first_name,
      cl_levels(
        cl_null(),
        cl_exact(),
        cl_columns_reversed('last_name', symmetrical = TRUE),
        cl_else()
      )
    ) |>
    il_block_on(last_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(last_name))

  pairs <- predict(model, threshold = 0.01)
  expect_s3_class(pairs, 'il_compared')
})
