# Sprint 5 — SQL generation: internal engine tests
# Translated from: test_linker_variants.py (join SQL),
# test_blocking.py (blocking SQL fragments),
# test_blocking_rule_composition.py (AND/OR SQL),
# test_sql_transform.py (SQL manipulation)

# These test internal SQL-generation functions. The functions are not
# exported; use  to access them.

test_that('cl_exact() generates correct equality SQL for a column', {
  # From: test_blocking.py — blocking_rule_sql == 'l."surname" = r."surname"'
  sql <- sql_for_comparison_level(cl_exact(), 'name', dialect = 'duckdb')
  expect_match(sql, 'l\\.', fixed = FALSE)
  expect_match(sql, 'r\\.', fixed = FALSE)
  expect_match(sql, 'name', fixed = TRUE)
})

test_that('cl_jaro_winkler() generates a CASE expression with similarity function', {
  sql <- sql_for_comparison_level(
    cl_jaro_winkler(0.9), 'first_name',
    dialect = 'duckdb'
  )
  expect_match(sql, 'jaro_winkler', fixed = TRUE)
  expect_match(sql, '0.9', fixed = TRUE)
})

test_that('cl_levenshtein() generates distance-based SQL', {
  sql <- sql_for_comparison_level(
    cl_levenshtein(1, 2), 'name',
    dialect = 'duckdb'
  )
  expect_match(sql, 'levenshtein', fixed = TRUE)
})

test_that('cl_date_diff(days(30)) generates date arithmetic SQL', {
  sql <- sql_for_comparison_level(
    cl_date_diff(days(30)), 'dob',
    dialect = 'duckdb'
  )
  expect_match(sql, '30', fixed = TRUE)
})

test_that('date-diff SQL uses PostgreSQL date arithmetic for postgres', {
  sql <- sql_for_comparison_level(
    cl_date_diff(days(30)), 'dob',
    dialect = 'postgres'
  )
  expect_match(sql, 'CAST\\(l\\."dob" AS DATE\\) - CAST\\(r\\."dob" AS DATE\\)')
  expect_no_match(sql, 'JULIANDAY', fixed = TRUE)
})

test_that('sql_gamma_case quotes non-syntactic column names', {
  comp <- list(
    columns = 'first name',
    method = cl_exact(),
    transform = NULL
  )
  sql <- sql_gamma_case(comp, 'duckdb')
  expect_match(sql, 'l\\."first name" IS NOT NULL')
  expect_match(sql, 'r\\."first name" IS NOT NULL')
  expect_match(sql, 'l\\."first name" = r\\."first name"')
})
