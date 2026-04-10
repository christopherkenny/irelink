test_that('il_transform creates a callable chain', {
  tf <- il_transform(tolower, trimws)
  expect_s3_class(tf, 'il_transform_chain')
  expect_true(is.function(tf))
  expect_equal(tf('  HELLO  '), 'hello')
})

test_that('il_transform requires at least 2 functions', {
  expect_error(il_transform(tolower), class = 'il_error_type')
})

test_that('il_transform rejects non-functions', {
  expect_error(il_transform(tolower, 42), class = 'il_error_type')
})

test_that('il_transform chain prints nicely', {
  tf <- il_transform(tolower, trimws)
  out <- capture.output(print(tf))
  expect_true(any(grepl('il_transform_chain', out)))
  expect_true(any(grepl('tolower -> trimws', out)))
})

test_that('sql_transform_col handles chains', {
  tf <- il_transform(tolower, trimws)
  result <- sql_transform_col('my_col', tf, 'duckdb')
  expect_equal(result, 'TRIM(LOWER(my_col))')
})

test_that('sql_transform_col handles chain with 3 steps', {
  tf <- il_transform(tolower, trimws, toupper)
  result <- sql_transform_col('x', tf, 'duckdb')
  expect_equal(result, 'UPPER(TRIM(LOWER(x)))')
})

test_that('transform_to_name works for chains', {
  tf <- il_transform(tolower, trimws)
  nm <- transform_to_name(tf)
  expect_equal(nm, 'tolower -> trimws')
})

test_that('il_compare accepts transform chains', {
  spec <- il_spec() |>
    il_compare(name, cl_exact(), transform = il_transform(tolower, trimws))
  comp <- spec$comparisons[[1]]
  expect_s3_class(comp$transform, 'il_transform_chain')
})

test_that('il_block_on accepts transform chains', {
  spec <- il_spec() |>
    il_block_on(name, .transform = il_transform(tolower, trimws))
  rule <- spec$blocking_rules[[1]]
  expect_s3_class(rule$transform, 'il_transform_chain')
})

test_that('transform chain works in R-side gamma computation', {
  tf <- il_transform(tolower, trimws)
  # Chain applied to values should match manual application
  vals <- c('  Alice  ', '  BOB  ', '  alice  ')
  expect_equal(tf(vals), c('alice', 'bob', 'alice'))
})

test_that('transform chain works end-to-end with DuckDB', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact(),
      transform = il_transform(tolower, trimws)
    )

  model <- il_model(fake_1000[1:20, ], spec = spec, con = con)
  # If it runs without error and produces SQL, the chain is working
  sql <- build_gamma_query(model, model$spec$blocking_rules)
  expect_match(sql, 'TRIM\\(LOWER')
})
