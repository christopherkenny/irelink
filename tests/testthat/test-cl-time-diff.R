# Tests for cl_time_diff() and time-related unit helpers

# --- Unit helpers: seconds(), minutes(), hours() -------------------------

test_that('seconds() creates a tagged value with correct class', {
  s <- seconds(30)
  expect_s3_class(s, 'il_seconds')
  expect_equal(s$value, 30)
  expect_equal(s$unit, 'seconds')
})

test_that('minutes() creates a tagged value with correct class', {
  m <- minutes(5)
  expect_s3_class(m, 'il_minutes')
  expect_equal(m$value, 5)
  expect_equal(m$unit, 'minutes')
})

test_that('hours() creates a tagged value with correct class', {
  h <- hours(2)
  expect_s3_class(h, 'il_hours')
  expect_equal(h$value, 2)
  expect_equal(h$unit, 'hours')
})

test_that('time unit helpers reject invalid input', {
  expect_error(seconds('ten'))
  expect_error(minutes(-1))
  expect_error(hours(NULL))
})

test_that('time unit helpers print informatively', {
  expect_output(print(seconds(30)), '30')
  expect_output(print(minutes(5)), '5')
  expect_output(print(hours(2)), '2')
})

# --- cl_time_diff() constructor -----------------------------------------

test_that('cl_time_diff() creates a comparison level', {
  td <- cl_time_diff(seconds(30), minutes(5))
  expect_s3_class(td, 'il_comparison_level')
  expect_equal(td$method, 'time_diff')
  expect_equal(td$thresholds, c(30, 5))
  expect_equal(td$units, c('seconds', 'minutes'))
})

test_that('cl_time_diff() accepts mixed units', {
  td <- cl_time_diff(minutes(5), hours(1), days(7))
  expect_equal(td$thresholds, c(5, 1, 7))
  expect_equal(td$units, c('minutes', 'hours', 'days'))
})

test_that('cl_time_diff() treats bare numerics as seconds', {
  td <- cl_time_diff(60)
  expect_equal(td$units, 'seconds')
  expect_equal(td$thresholds, 60)
})

test_that('cl_time_diff() errors with no arguments', {
  expect_error(cl_time_diff(), 'requires at least one threshold')
})

# --- time_diff_to_seconds() internal helper -----------------------------

test_that('time_diff_to_seconds converts units correctly', {
  expect_equal(time_diff_to_seconds(1, 'seconds'), 1)
  expect_equal(time_diff_to_seconds(1, 'minutes'), 60)
  expect_equal(time_diff_to_seconds(1, 'hours'), 3600)
  expect_equal(time_diff_to_seconds(1, 'days'), 86400)
  expect_equal(time_diff_to_seconds(2, 'hours'), 7200)
})

# --- R-side gamma computation -------------------------------------------

test_that('cl_time_diff computes correct gammas for timestamps', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    ts = c(
      '2024-01-01 12:00:00',
      '2024-01-01 12:02:00',
      '2024-01-01 13:00:00',
      '2024-01-02 12:00:00'
    ),
    stringsAsFactors = FALSE
  )

  spec <- il_spec() |>
    il_compare(ts, cl_time_diff(minutes(5), hours(2)))

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)

  params <- model$params$comparisons
  # With 2 thresholds: gamma levels 0, 1, 2
  expect_true(all(c(0L, 1L, 2L) %in% params$gamma_level))
})

# --- SQL-side gamma computation (DuckDB) --------------------------------

test_that('cl_time_diff SQL generation uses EPOCH for DuckDB', {
  td <- cl_time_diff(minutes(5))
  comp <- list(columns = 'ts', method = td, transform = NULL)
  sql <- sql_gamma_case(comp, 'duckdb')
  expect_match(sql, 'EPOCH', fixed = TRUE)
  expect_match(sql, '300', fixed = TRUE) # 5 * 60 seconds
})

test_that('cl_time_diff SQL generation uses EXTRACT for postgres', {
  td <- cl_time_diff(hours(1))
  comp <- list(columns = 'ts', method = td, transform = NULL)
  sql <- sql_gamma_case(comp, 'postgres')
  expect_match(sql, 'EXTRACT', fixed = TRUE)
  expect_match(sql, '3600', fixed = TRUE) # 1 * 3600 seconds
})
