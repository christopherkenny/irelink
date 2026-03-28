# Sprint 1 — Foundation: il_spec, unit helpers, S3 classes
# Translated from splink test patterns; no direct splink equivalent
# for structural S3 tests, but follows the contract defined in
# inst/refs/04-irelink-core-interface.md and 08-sprints.md.

test_that('il_spec() creates an il_spec object', {
 spec <- il_spec()
 expect_s3_class(spec, 'il_spec')
})

test_that('is_il_spec() returns TRUE for specs, FALSE for others', {

 expect_true(is_il_spec(il_spec()))
 expect_false(is_il_spec('not a spec'))
 expect_false(is_il_spec(42))
 expect_false(is_il_spec(NULL))
 expect_false(is_il_spec(list()))
})

test_that('print.il_spec() produces output without error', {
 spec <- il_spec()
 expect_output(print(spec))
})

test_that('il_spec() creates a spec with empty comparisons and blocking rules', {
 spec <- il_spec()
 # A fresh spec should have no comparisons or blocking rules
 expect_length(spec$comparisons, 0)
 expect_length(spec$blocking_rules, 0)
})
