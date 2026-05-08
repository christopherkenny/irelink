# Sprint 2 — Similarity-based comparison level constructors
# Translated from: test_comparison_level_lib.py, test_comparison_lib.py,
# test_date_levels_and_comparisons.py, test_km_distance_level.py,
# test_array_columns.py, test_comparison_level.py, test_regex_param.py

# --- cl_exact() -----------------------------------------------------------

test_that('cl_exact() creates a comparison level object', {
  lev <- cl_exact()
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'exact')
})

test_that('comparison level constructors accept term_frequency flag', {
  constructors <- list(
    cl_exact(term_frequency = TRUE),
    cl_jaro_winkler(0.9, term_frequency = TRUE),
    cl_jaro(0.85, term_frequency = TRUE),
    cl_levenshtein(1, term_frequency = TRUE),
    cl_damerau_levenshtein(1, term_frequency = TRUE)
  )
  tf_flags <- vapply(constructors, function(lev) lev$term_frequency, logical(1))
  expect_true(all(tf_flags))
})

# --- cl_jaro_winkler() / cl_jaro() ----------------------------------------

test_that('cl_jaro_winkler() stores thresholds in descending order', {
  lev <- cl_jaro_winkler(0.9, 0.7)
  expect_equal(lev$thresholds, c(0.9, 0.7))
})

test_that('cl_jaro_winkler() warns on non-descending thresholds', {
  expect_warning(cl_jaro_winkler(0.7, 0.9))
})

test_that('cl_jaro_winkler() with single threshold works', {
  lev <- cl_jaro_winkler(0.88)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'jaro_winkler')
  expect_equal(lev$thresholds, 0.88)
})

test_that('cl_jaro() creates a jaro-only comparison level', {
  lev <- cl_jaro(0.85)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'jaro')
})

# --- cl_levenshtein() / cl_damerau_levenshtein() --------------------------
# From: test_comparison_level_lib.py::test_levenshtein_level,
# test_damerau_levenshtein_level

test_that('cl_levenshtein() stores integer distance thresholds', {
  lev <- cl_levenshtein(1, 2, 3)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'levenshtein')
  expect_equal(lev$thresholds, c(1, 2, 3))
})

test_that('cl_damerau_levenshtein() creates a damerau-levenshtein level', {
  lev <- cl_damerau_levenshtein(1, 2)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'damerau_levenshtein')
})

# --- cl_jaccard() / cl_cosine() -------------------------------------------
# From: test_comparison_level_lib.py::test_cosine_similarity_level

test_that('cl_jaccard() creates a jaccard similarity level', {
  lev <- cl_jaccard(0.8, 0.5)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'jaccard')
  expect_equal(lev$thresholds, c(0.8, 0.5))
})

test_that('cl_jaccard() and cl_cosine() have active SQL gamma support', {
  jaccard_sql <- sql_gamma_case(
    list(columns = 'name', method = cl_jaccard(0.8), transform = NULL),
    dialect = 'duckdb'
  )
  cosine_sql <- sql_gamma_case(
    list(columns = 'name', method = cl_cosine(0.8), transform = NULL),
    dialect = 'duckdb'
  )
  expect_match(jaccard_sql, 'jaccard', fixed = TRUE)
  expect_match(cosine_sql, 'cosine_similarity', fixed = TRUE)
  expect_false(grepl('l.name = r.name', jaccard_sql, fixed = TRUE))
  expect_false(grepl('l.name = r.name', cosine_sql, fixed = TRUE))
})

test_that('cl_cosine() creates a cosine similarity level', {
  lev <- cl_cosine(0.9, 0.7, 0.5)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'cosine')
  expect_equal(lev$thresholds, c(0.9, 0.7, 0.5))
})

# --- cl_numeric_diff() / cl_pct_diff() ------------------------------------
# From: test_comparison_level_lib.py::test_absolute_difference, test_perc_difference

test_that('cl_numeric_diff() stores absolute-difference thresholds', {
  lev <- cl_numeric_diff(0, 5, 10, 20, 50)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'numeric_diff')
  expect_equal(lev$thresholds, c(0, 5, 10, 20, 50))
})

test_that('cl_pct_diff() stores percentage-difference thresholds', {
  lev <- cl_pct_diff(0.10, 0.20, 0.30)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'pct_diff')
})

test_that('pct_diff uses strict < (not <=) matching splink', {
  # A pair with exactly 10% difference should NOT match a 0.10 threshold
  sql <- sql_gamma_case(
    list(columns = 'val', method = cl_pct_diff(0.10)),
    dialect = 'duckdb'
  )
  # The SQL should use < not <=
  expect_true(grepl('< 0.1', sql))
  expect_false(grepl('<= 0.1', sql))
})

# --- cl_date_diff() -------------------------------------------------------
# From: test_date_levels_and_comparisons.py

test_that('cl_date_diff() accepts unit-helper thresholds', {
  lev <- cl_date_diff(days(30), days(365))
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'date_diff')
})

test_that('cl_date_diff() accepts bare numerics as days', {
  lev <- cl_date_diff(30, 365)
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_date_diff() accepts mixed metric thresholds', {
  lev <- cl_date_diff(days(1), months(1), years(1), years(10))
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_date_diff() rejects negative thresholds', {
  expect_error(cl_date_diff(days(-1)))
  expect_error(cl_date_diff(-1))
})

test_that('cl_date_diff() rejects invalid metrics', {
  # Only days/months/years are valid
  expect_error(cl_date_diff(km(30)))
})

# --- cl_distance_km() -----------------------------------------------------
# From: test_km_distance_level.py

test_that('cl_distance_km() creates a geographic distance level', {
  lev <- cl_distance_km(km(0.1), km(1), km(10), km(300))
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'distance_km')
})

test_that('cl_distance_km() accepts bare numerics as km', {
  lev <- cl_distance_km(1, 5, 10)
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_distance_km() accepts miles', {
  lev <- cl_distance_km(mi(1), mi(5))
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_distance_km() rejects negative bare numerics', {
  expect_error(cl_distance_km(-1))
})

test_that('cl_distance_km() uses a two-column comparison and computes R gamma', {
  spec <- il_spec() |>
    il_compare(c(lat, lon), cl_distance_km(km(1), km(500)))

  expect_equal(spec$comparisons[[1]]$columns, c('lat', 'lon'))
  expect_equal(comparison_name(spec$comparisons[[1]]), 'lat_lon')

  pairs <- data.frame(
    l_lat = c(0, 0),
    l_lon = c(0, 0),
    r_lat = c(0, 10),
    r_lon = c(0, 10)
  )
  gamma <- compute_gamma_matrix(pairs, spec$comparisons)
  expect_equal(colnames(gamma), 'lat_lon')
  expect_equal(gamma[, 1], c(2L, 0L))
})

test_that('cl_distance_km() has active SQL gamma support', {
  sql <- sql_gamma_case(
    list(columns = c('lat', 'lon'), method = cl_distance_km(km(1)), transform = NULL),
    dialect = 'duckdb'
  )
  expect_match(sql, '6371', fixed = TRUE)
  expect_match(sql, 'RADIANS', fixed = TRUE)
})

# --- cl_array_intersect() -------------------------------------------------
# From: test_array_columns.py::test_array_comparison_1

test_that('cl_array_intersect() creates an array intersection level', {
  lev <- cl_array_intersect(4, 3, 2, 1)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'array_intersect')
})

test_that('cl_array_intersect() rejects negative thresholds', {
  expect_error(cl_array_intersect(-1, 2))
})

test_that('cl_array_intersect() computes shared-element R gamma', {
  gamma <- compute_gamma(
    c('a,b,c', 'a,b', 'x'),
    c('b,c,d', 'c,d', 'y'),
    cl_array_intersect(2, 1)
  )
  expect_equal(gamma, c(2L, 0L, 0L))
})

test_that('cl_array_intersect() has active SQL gamma support', {
  sql <- sql_gamma_case(
    list(columns = 'tags', method = cl_array_intersect(2, 1), transform = NULL),
    dialect = 'duckdb'
  )
  expect_match(sql, 'ARRAY_INTERSECT', fixed = TRUE)
  expect_match(sql, 'ARRAY_LENGTH', fixed = TRUE)
})

# --- cl_array_min_distance() ----------------------------------------------

test_that('cl_array_min_distance() creates a comparison level', {
  lev <- cl_array_min_distance('jaro_winkler', 0.9, 0.7)
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'array_min_distance')
  expect_equal(lev$fn, 'jaro_winkler')
  expect_equal(lev$thresholds, c(0.9, 0.7))
})

test_that('cl_array_min_distance() stores levenshtein thresholds', {
  lev <- cl_array_min_distance('levenshtein', 1, 2)
  expect_equal(lev$fn, 'levenshtein')
  expect_equal(lev$thresholds, c(1, 2))
})

test_that('cl_array_min_distance() rejects out-of-range jaro_winkler thresholds', {
  expect_snapshot(error = TRUE, cl_array_min_distance('jaro_winkler', 1.5))
})

test_that('cl_array_min_distance() rejects negative levenshtein thresholds', {
  expect_snapshot(error = TRUE, cl_array_min_distance('levenshtein', -1))
})

test_that('cl_array_min_distance() rejects empty thresholds', {
  expect_snapshot(error = TRUE, cl_array_min_distance('jaro_winkler'))
})

test_that('cl_array_min_distance() R fallback computes correct gamma', {
  lev <- cl_array_min_distance('jaro_winkler', 0.9, 0.7)
  # "john" vs "jon" jaro-winkler ~ 0.93: should score 2
  gamma <- compute_gamma('john', 'jon', lev)
  expect_equal(gamma, 2L)
  # "abc" vs "xyz": very low similarity, should score 0
  gamma_no <- compute_gamma('abc', 'xyz', lev)
  expect_equal(gamma_no, 0L)
})

test_that('cl_array_min_distance() R fallback uses best pair across arrays', {
  lev <- cl_array_min_distance('jaro_winkler', 0.9)
  # comma-separated arrays: best pair is "john"/"john" = 1.0
  gamma <- compute_gamma('alice,john', 'bob,john', lev)
  expect_equal(gamma, 1L)
})

# --- cl_custom() ----------------------------------------------------------

test_that('cl_custom() stores a raw SQL expression', {
  lev <- cl_custom('SUBSTR(l.postcode, 1, 3) = SUBSTR(r.postcode, 1, 3)')
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'custom')
})

test_that('cl_custom() has active SQL gamma support and no silent R fallback', {
  sql <- sql_gamma_case(
    list(columns = 'score', method = cl_custom('l.score + r.score > 10'), transform = NULL),
    dialect = 'duckdb'
  )
  expect_match(sql, 'l.score + r.score > 10', fixed = TRUE)
  expect_error(compute_gamma(6, 6, cl_custom('l.score + r.score > 10')))
})

# --- Threshold validation (cross-cutting) ---------------------------------

test_that('similarity thresholds must be between 0 and 1', {
  expect_error(cl_jaro_winkler(1.5))
  expect_error(cl_jaccard(-0.1))
  expect_error(cl_cosine(2.0))
})

test_that('distance thresholds must be non-negative', {
  expect_error(cl_levenshtein(-1))
  expect_error(cl_numeric_diff(-5))
})
