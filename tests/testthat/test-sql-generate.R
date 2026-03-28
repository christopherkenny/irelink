# Sprint 5 — SQL generation: internal engine tests
# Translated from: test_linker_variants.py (join SQL),
# test_blocking.py (blocking SQL fragments),
# test_blocking_rule_composition.py (AND/OR SQL),
# test_sql_transform.py (SQL manipulation)

# These test internal SQL-generation functions. The functions are not
# exported; use irelink::: to access them.

test_that('cl_exact() generates correct equality SQL for a column', {
 # From: test_blocking.py — blocking_rule_sql == 'l."surname" = r."surname"'
 sql <- irelink:::sql_for_comparison_level(cl_exact(), 'name', dialect = 'duckdb')
 expect_match(sql, 'l\\.', fixed = FALSE)
 expect_match(sql, 'r\\.', fixed = FALSE)
 expect_match(sql, 'name', fixed = TRUE)
})

test_that('cl_jaro_winkler() generates a CASE expression with similarity function', {
 sql <- irelink:::sql_for_comparison_level(
 cl_jaro_winkler(0.9), 'first_name',
 dialect = 'duckdb'
 )
 expect_match(sql, 'jaro_winkler', fixed = TRUE)
 expect_match(sql, '0.9', fixed = TRUE)
})

test_that('cl_levenshtein() generates distance-based SQL', {
 sql <- irelink:::sql_for_comparison_level(
 cl_levenshtein(1, 2), 'name',
 dialect = 'duckdb'
 )
 expect_match(sql, 'levenshtein', fixed = TRUE)
})

test_that('cl_date_diff(days(30)) generates date arithmetic SQL', {
 sql <- irelink:::sql_for_comparison_level(
 cl_date_diff(days(30)), 'dob',
 dialect = 'duckdb'
 )
 expect_match(sql, '30', fixed = TRUE)
})

test_that('block_on() generates equality SQL for blocking', {
 # From: test_blocking.py — 'l."first_name" = r."first_name"'
 rule <- block_on(first_name)
 sql <- irelink:::sql_for_blocking_rule(rule, dialect = 'duckdb')
 expect_match(sql, 'first_name', fixed = TRUE)
})

test_that('multiple blocking rules produce OR-composed SQL', {
 # From: test_blocking_rule_composition.py — OR composition
 rules <- list(block_on(first_name), block_on(surname))
 sql <- irelink:::sql_for_blocking_rules(rules, dialect = 'duckdb')
 expect_match(sql, 'OR', fixed = TRUE)
})

test_that('block_on(col1, col2) produces AND-composed SQL', {
 # From: test_blocking_rule_composition.py — AND composition
 rule <- block_on(first_name, surname)
 sql <- irelink:::sql_for_blocking_rule(rule, dialect = 'duckdb')
 expect_match(sql, 'AND', fixed = TRUE)
})

test_that('dedupe join condition excludes self-pairs', {
 # From: test_linker_variants.py::test_dedupe_only_join_condition
 sql <- irelink:::sql_join_condition('dedupe')
 expect_match(sql, '<', fixed = TRUE) # l.unique_id < r.unique_id
})

test_that('link-only join condition pairs records across datasets', {
 # From: test_linker_variants.py::test_link_only_two_join_condition
 sql <- irelink:::sql_join_condition('link')
 expect_true(nchar(sql) > 0)
})
