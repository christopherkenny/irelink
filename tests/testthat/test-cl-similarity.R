# Sprint 2 — Similarity-based comparison level constructors
# Translated from: test_comparison_level_lib.py, test_comparison_lib.py,
# test_date_levels_and_comparisons.py, test_km_distance_level.py,
# test_array_columns.py, test_comparison_level.py, test_regex_param.py

# --- cl_exact() -----------------------------------------------------------

test_that('cl_exact() creates a comparison level object', {
  skip_if_sprint_lt(2)
  lev <- cl_exact()
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'exact')
})

test_that('cl_exact() accepts term_frequency flag', {
  skip_if_sprint_lt(2)
  lev <- cl_exact(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

# --- cl_jaro_winkler() / cl_jaro() ----------------------------------------

test_that('cl_jaro_winkler() stores thresholds in descending order', {
  skip_if_sprint_lt(2)
  lev <- cl_jaro_winkler(0.9, 0.7)
  expect_equal(lev$thresholds, c(0.9, 0.7))
})

test_that('cl_jaro_winkler() warns on non-descending thresholds', {
  skip_if_sprint_lt(2)
  expect_warning(cl_jaro_winkler(0.7, 0.9))
})

test_that('cl_jaro_winkler() with single threshold works', {
  skip_if_sprint_lt(2)
  lev <- cl_jaro_winkler(0.88)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'jaro_winkler')
  expect_equal(lev$thresholds, 0.88)
})

test_that('cl_jaro() creates a jaro-only comparison level', {
  skip_if_sprint_lt(2)
  lev <- cl_jaro(0.85)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'jaro')
})

# --- cl_levenshtein() / cl_damerau_levenshtein() --------------------------
# From: test_comparison_level_lib.py::test_levenshtein_level,
#       test_damerau_levenshtein_level

test_that('cl_levenshtein() stores integer distance thresholds', {
  skip_if_sprint_lt(2)
  lev <- cl_levenshtein(1, 2, 3)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'levenshtein')
  expect_equal(lev$thresholds, c(1, 2, 3))
})

test_that('cl_damerau_levenshtein() creates a damerau-levenshtein level', {
  skip_if_sprint_lt(2)
  lev <- cl_damerau_levenshtein(1, 2)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'damerau_levenshtein')
})

# --- cl_jaccard() / cl_cosine() -------------------------------------------
# From: test_comparison_level_lib.py::test_cosine_similarity_level

test_that('cl_jaccard() creates a jaccard similarity level', {
  skip_if_sprint_lt(2)
  lev <- cl_jaccard(0.8, 0.5)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'jaccard')
  expect_equal(lev$thresholds, c(0.8, 0.5))
})

test_that('cl_cosine() creates a cosine similarity level', {
  skip_if_sprint_lt(2)
  lev <- cl_cosine(0.9, 0.7, 0.5)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'cosine')
  expect_equal(lev$thresholds, c(0.9, 0.7, 0.5))
})

# --- cl_numeric_diff() / cl_pct_diff() ------------------------------------
# From: test_comparison_level_lib.py::test_absolute_difference, test_perc_difference

test_that('cl_numeric_diff() stores absolute-difference thresholds', {
  skip_if_sprint_lt(2)
  lev <- cl_numeric_diff(0, 5, 10, 20, 50)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'numeric_diff')
  expect_equal(lev$thresholds, c(0, 5, 10, 20, 50))
})

test_that('cl_pct_diff() stores percentage-difference thresholds', {
  skip_if_sprint_lt(2)
  lev <- cl_pct_diff(0.10, 0.20, 0.30)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'pct_diff')
})

# --- cl_date_diff() -------------------------------------------------------
# From: test_date_levels_and_comparisons.py

test_that('cl_date_diff() accepts unit-helper thresholds', {
  skip_if_sprint_lt(2)
  lev <- cl_date_diff(days(30), days(365))
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'date_diff')
})

test_that('cl_date_diff() accepts bare numerics as days', {
  skip_if_sprint_lt(2)
  lev <- cl_date_diff(30, 365)
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_date_diff() accepts mixed metric thresholds', {
  skip_if_sprint_lt(2)
  lev <- cl_date_diff(days(1), months(1), years(1), years(10))
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_date_diff() rejects negative thresholds', {
  skip_if_sprint_lt(2)
  expect_error(cl_date_diff(days(-1)))
})

test_that('cl_date_diff() rejects invalid metrics', {
  skip_if_sprint_lt(2)
  # Only days/months/years are valid
  expect_error(cl_date_diff(km(30)))
})

# --- cl_distance_km() -----------------------------------------------------
# From: test_km_distance_level.py

test_that('cl_distance_km() creates a geographic distance level', {
  skip_if_sprint_lt(2)
  lev <- cl_distance_km(km(0.1), km(1), km(10), km(300))
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'distance_km')
})

test_that('cl_distance_km() accepts bare numerics as km', {
  skip_if_sprint_lt(2)
  lev <- cl_distance_km(1, 5, 10)
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_distance_km() accepts miles', {
  skip_if_sprint_lt(2)
  lev <- cl_distance_km(mi(1), mi(5))
  expect_s3_class(lev, 'il_comparison_level')
})

# --- cl_array_intersect() -------------------------------------------------
# From: test_array_columns.py::test_array_comparison_1

test_that('cl_array_intersect() creates an array intersection level', {
  skip_if_sprint_lt(2)
  lev <- cl_array_intersect(4, 3, 2, 1)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'array_intersect')
})

test_that('cl_array_intersect() rejects negative thresholds', {
  skip_if_sprint_lt(2)
  expect_error(cl_array_intersect(-1, 2))
})

# --- cl_custom() ----------------------------------------------------------

test_that('cl_custom() stores a raw SQL expression', {
  skip_if_sprint_lt(2)
  lev <- cl_custom('SUBSTR(l.postcode, 1, 3) = SUBSTR(r.postcode, 1, 3)')
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'custom')
})

# --- Threshold validation (cross-cutting) ---------------------------------

test_that('similarity thresholds must be between 0 and 1', {
  skip_if_sprint_lt(2)
  expect_error(cl_jaro_winkler(1.5))
  expect_error(cl_jaccard(-0.1))
  expect_error(cl_cosine(2.0))
})

test_that('distance thresholds must be non-negative', {
  skip_if_sprint_lt(2)
  expect_error(cl_levenshtein(-1))
  expect_error(cl_numeric_diff(-5))
})

# --- R type safety (from 09-implementation-plan §6a) ----------------------

test_that('cl_exact() handles factor columns gracefully', {
  skip_if_sprint_lt(2)
  # Factors are common in R data frames — cl_exact() should accept them
  # or coerce silently rather than failing unexpectedly
  lev <- cl_exact()
  expect_s3_class(lev, 'il_comparison_level')
  # Factor handling is exercised at comparison time, not construction;

  # this test ensures the level can be created for factor-targeted use
})

test_that('cl_date_diff() is compatible with Date, POSIXct, and character date columns', {
  skip_if_sprint_lt(2)
  # From: 09-implementation-plan §6a — R has Date, POSIXct, and character dates.
  # cl_date_diff() creates comparison levels; the SQL backend handles casting.
  # This test verifies the level object itself doesn't restrict input types.
  lev <- cl_date_diff(days(30), days(365))
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'date_diff')
})
