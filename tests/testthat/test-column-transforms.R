test_that('il_substr returns correct substring', {
  tf <- il_substr(1, 3)
  expect_equal(tf('Hello'), 'Hel')
  expect_equal(tf('Hi'), 'Hi')
})

test_that('il_substr SQL generation', {
  tf <- il_substr(2, 4)
  sql <- sql_transform_col('l.name', tf, 'duckdb')
  expect_equal(sql, 'SUBSTRING(l.name, 2, 4)')
})

test_that('il_regex_extract returns match or NA', {
  tf <- il_regex_extract('[0-9]+')
  expect_equal(tf('abc123def'), '123')
  expect_true(is.na(tf('abcdef')))
})

test_that('il_regex_extract SQL wraps in NULLIF', {
  tf <- il_regex_extract('[0-9]+', 1L)
  sql <- sql_transform_col('l.phone', tf, 'duckdb')
  expect_match(sql, 'regexp_extract')
  expect_match(sql, 'NULLIF')
})

test_that('il_nullif replaces value with NA', {
  tf <- il_nullif('')
  expect_true(is.na(tf('')))
  expect_equal(tf('hello'), 'hello')
})

test_that('il_nullif SQL generation', {
  tf <- il_nullif('')
  sql <- sql_transform_col('l.city', tf, 'duckdb')
  expect_equal(sql, "NULLIF(l.city, '')")
})

test_that('il_cast_to_string casts to character', {
  tf <- il_cast_to_string()
  expect_equal(tf(42), '42')
  expect_equal(tf(TRUE), 'TRUE')
})

test_that('il_cast_to_string SQL generation', {
  tf <- il_cast_to_string()
  sql <- sql_transform_col('l.dob', tf, 'duckdb')
  expect_equal(sql, 'CAST(l.dob AS VARCHAR)')
})

test_that('il_try_parse_date parses dates in R', {
  tf <- il_try_parse_date('%Y-%m-%d')
  expect_equal(tf('2024-01-15'), '2024-01-15')
})

test_that('il_try_parse_date DuckDB SQL uses try_strptime', {
  tf <- il_try_parse_date('%Y-%m-%d')
  sql <- sql_transform_col('l.dob', tf, 'duckdb')
  expect_match(sql, 'try_strptime')
})

test_that('il_try_parse_date PostgreSQL SQL uses TO_DATE', {
  tf <- il_try_parse_date('%Y-%m-%d')
  sql <- sql_transform_col('l.dob', tf, 'postgres')
  expect_match(sql, 'TO_DATE')
})

test_that('il_array_element extracts first/last', {
  tf_first <- il_array_element('first')
  tf_last <- il_array_element('last')
  expect_equal(tf_first(list(c('a', 'b', 'c'))), 'a')
  expect_equal(tf_last(list(c('a', 'b', 'c'))), 'c')
})

test_that('il_array_element SQL generation', {
  tf_first <- il_array_element('first')
  tf_last <- il_array_element('last')
  expect_equal(sql_transform_col('l.arr', tf_first), 'l.arr[1]')
  expect_equal(sql_transform_col('l.arr', tf_last), 'l.arr[-1]')
})

test_that('column transforms serialize to name', {
  expect_equal(transform_to_name(il_substr(1, 3)), 'il_substr(1,3)')
  expect_equal(transform_to_name(il_nullif('')), 'il_nullif("")')
  expect_equal(transform_to_name(il_cast_to_string()), 'il_cast_to_string()')
})

test_that('column transforms compose with il_transform', {
  tf <- il_transform(il_substr(1, 5), tolower)
  expect_s3_class(tf, 'il_transform_chain')
  sql <- sql_transform_col('l.name', tf, 'duckdb')
  expect_equal(sql, 'LOWER(SUBSTRING(l.name, 1, 5))')
})

test_that('il_substr validates inputs', {
  expect_error(il_substr(0, 3))
  expect_error(il_substr(1, 0))
  expect_error(il_substr('a', 3))
})

test_that('il_nullif validates inputs', {
  expect_error(il_nullif(42))
})

test_that('column transforms work in DuckDB blocking', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- data.frame(
    unique_id = 1:6,
    name = c('Jonathan', 'Jon', 'Jonathan', 'Jane', 'Janet', 'Jane'),
    code = c('', 'ABC', '', 'DEF', 'DEF', ''),
    stringsAsFactors = FALSE
  )
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name, .transform = il_substr(1, 3))
  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(name))
  pairs <- predict(model, threshold = 0)
  expect_true(nrow(pairs) > 0)
})
