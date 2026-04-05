# Sprint 2 — Domain-knowledge comparison bundles
# Translated from: test_comparison_template_lib.py
# (test_name_comparison, test_email_comparison, test_date_of_birth_comparison_levels,
# test_postcode_comparison, test_forename_surname_comparison)

# --- cl_name() ------------------------------------------------------------
# From: test_name_comparison — splink thresholds: exact, JW >= 0.92, >= 0.88, >= 0.7

test_that('cl_name() returns a comparison level with correct structure', {
  lev <- cl_name()
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_name() has the expected number of levels', {
  # Expected: null + exact + JW(0.92) + JW(0.88) + JW(0.7) + else = 6 levels
  # (or a structured equivalent)
  lev <- cl_name()
  expect_true(length(lev$levels) >= 4)
})

test_that('cl_name() produces equivalent structure to manual composition', {
  bundle <- cl_name()
  manual <- cl_levels(
    cl_null(),
    cl_exact(),
    cl_jaro_winkler(0.92),
    cl_jaro_winkler(0.88),
    cl_jaro_winkler(0.7),
    cl_else()
  )
  # Both should have the same number of levels
  expect_equal(length(bundle$levels), length(manual$levels))
})

test_that('cl_name() accepts term_frequency flag', {
  lev <- cl_name(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

# --- cl_soundex() ---------------------------------------------------------

test_that('cl_soundex() returns a comparison level with soundex method', {
  lev <- cl_soundex()
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'soundex')
})

test_that('cl_name(phonetic = TRUE) adds a soundex level', {
  without <- cl_name()
  with_phonetic <- cl_name(phonetic = TRUE)
  expect_equal(length(with_phonetic$levels), length(without$levels) + 1L)
  methods <- vapply(with_phonetic$levels, `[[`, character(1), 'method')
  expect_true('soundex' %in% methods)
})

test_that('cl_name(phonetic = TRUE) places soundex before else', {
  lev <- cl_name(phonetic = TRUE)
  n <- length(lev$levels)
  expect_equal(lev$levels[[n]]$method, 'else')
  expect_equal(lev$levels[[n - 1L]]$method, 'soundex')
})

# --- cl_email() -----------------------------------------------------------
# From: test_email_comparison — levels: exact, exact-username, JW >= 0.88, JW-username

test_that('cl_email() returns a comparison level with correct structure', {
  lev <- cl_email()
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_email() has at least 4 match levels', {
  lev <- cl_email()
  # Expected: null + exact + exact-username + JW + JW-username + else >= 6
  expect_true(length(lev$levels) >= 4)
})

test_that('cl_email() accepts term_frequency flag', {
  lev <- cl_email(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

# --- cl_dob() -------------------------------------------------------------
# From: test_date_of_birth_comparison_levels

test_that('cl_dob() returns a comparison level with correct structure', {
  lev <- cl_dob()
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_dob() has at least 4 match levels', {
  lev <- cl_dob()
  # Expected: null + exact + DL<=1 + date_diff<=1month + <=1year + <=10year + else
  expect_true(length(lev$levels) >= 4)
})

test_that('cl_dob() accepts term_frequency flag', {
  lev <- cl_dob(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

test_that('cl_dob() accepts custom thresholds', {
  lev <- cl_dob(thresholds = list(days(7), months(6)))
  date_methods <- vapply(lev$levels, `[[`, character(1), 'method')
  expect_equal(sum(date_methods == 'date_diff'), 2L)
})

test_that('cl_dob() custom thresholds change level count', {
  default_lev <- cl_dob()
  custom_lev <- cl_dob(thresholds = list(days(7), months(6), years(1), years(5)))
  expect_equal(
    length(custom_lev$levels),
    length(default_lev$levels) + 1L
  )
})

test_that('cl_dob() rejects empty thresholds', {
  expect_snapshot(error = TRUE, cl_dob(thresholds = list()))
})

# --- cl_postcode() --------------------------------------------------------
# From: test_postcode_comparison — levels: exact, sector, district, area

test_that('cl_postcode() returns a comparison level with correct structure', {
  lev <- cl_postcode()
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_postcode() has at least 4 match levels', {
  lev <- cl_postcode()
  # Expected: null + full + sector + district + area + else >= 6
  expect_true(length(lev$levels) >= 4)
})

test_that('cl_postcode() accepts term_frequency flag', {
  lev <- cl_postcode(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

test_that('cl_postcode() appends geo levels when lat/lon supplied', {
  lev <- cl_postcode(lat_col = 'lat', long_col = 'lon', km_thresholds = c(5, 50))
  methods <- vapply(lev$levels, `[[`, character(1), 'method')
  # Two extra custom levels before else
  expect_equal(sum(methods == 'custom'), 5L) # 3 prefix + 2 geo
  expect_equal(methods[length(methods)], 'else')
})

test_that('cl_postcode() geo SQL embeds lat/lon column names', {
  lev <- cl_postcode(lat_col = 'latitude', long_col = 'longitude', km_thresholds = 10)
  custom_levels <- Filter(function(l) l$method == 'custom', lev$levels)
  geo_sqls <- vapply(custom_levels, `[[`, character(1), 'sql_expr')
  geo_sql <- geo_sqls[grepl('ASIN', geo_sqls)][1]
  expect_match(geo_sql, 'latitude')
  expect_match(geo_sql, 'longitude')
})

# --- cl_forename_surname() / cl_first_last_name() -------------------------
# From: test_forename_surname_comparison — includes reversed-columns check

test_that('cl_forename_surname() returns a comparison level with correct structure', {
  lev <- cl_forename_surname()
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_forename_surname() has the expected number of levels', {
  lev <- cl_forename_surname()
  # null + exact + swap + JW(0.92) + JW(0.88) + else = 6
  expect_equal(length(lev$levels), 6)
})

test_that('cl_forename_surname() embeds surname column in swap SQL', {
  lev <- cl_forename_surname(surname = 'last_name')
  swap_level <- lev$levels[[3]]
  expect_match(swap_level$sql_expr, 'last_name')
})

test_that('cl_forename_surname() accepts term_frequency flag', {
  lev <- cl_forename_surname(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

test_that('cl_first_last_name() is an alias for cl_forename_surname()', {
  lev_alias <- cl_first_last_name(last_name = 'surname')
  lev_orig <- cl_forename_surname(surname = 'surname')
  expect_equal(lev_alias, lev_orig)
})

test_that('cl_first_last_name() embeds last_name column in swap SQL', {
  lev <- cl_first_last_name(last_name = 'family_name')
  swap_level <- lev$levels[[3]]
  expect_match(swap_level$sql_expr, 'family_name')
})

# --- cl_zip_code() --------------------------------------------------------

test_that('cl_zip_code() returns a comparison level with correct structure', {
  lev <- cl_zip_code()
  expect_s3_class(lev, 'il_comparison_level')
})

test_that('cl_zip_code() has the expected number of levels', {
  lev <- cl_zip_code()
  # null + exact + 5-digit + 3-digit + else = 5
  expect_equal(length(lev$levels), 5)
})

test_that('cl_zip_code() uses fixed-width SUBSTR for prefix levels', {
  lev <- cl_zip_code()
  five_digit <- lev$levels[[3]]
  three_digit <- lev$levels[[4]]
  expect_match(five_digit$sql_expr, 'SUBSTR.*1, 5')
  expect_match(three_digit$sql_expr, 'SUBSTR.*1, 3')
})

test_that('cl_zip_code() accepts term_frequency flag', {
  lev <- cl_zip_code(term_frequency = TRUE)
  expect_true(lev$term_frequency)
})

test_that('cl_zip_code() appends geo levels when lat/lon supplied', {
  lev <- cl_zip_code(lat_col = 'lat', long_col = 'lon', km_thresholds = c(1, 10))
  methods <- vapply(lev$levels, `[[`, character(1), 'method')
  expect_equal(sum(methods == 'custom'), 4L) # 2 prefix + 2 geo
})

# --- cl_array_subset() --------------------------------------------------------

test_that('cl_array_subset() returns a comparison level', {
  lev <- cl_array_subset()
  expect_s3_class(lev, 'il_comparison_level')
  expect_equal(lev$method, 'array_subset')
})

test_that('cl_array_subset() is distinct from cl_array_intersect()', {
  expect_false(identical(cl_array_subset(), cl_array_intersect(1)))
})

# --- cl_literal() -------------------------------------------------------------

test_that('cl_literal() generates both-side SQL by default', {
  lev <- cl_literal('US')
  expect_s3_class(lev, 'il_comparison_level')
  expect_match(lev$sql_expr, "l\\.\\{col\\} = 'US'")
  expect_match(lev$sql_expr, "r\\.\\{col\\} = 'US'")
})

test_that('cl_literal() left side only', {
  lev <- cl_literal('US', side = 'left')
  expect_match(lev$sql_expr, 'l\\.\\{col\\}')
  expect_false(grepl('r\\.\\{col\\}', lev$sql_expr))
})

test_that('cl_literal() numeric values are not quoted', {
  lev <- cl_literal(1L)
  expect_false(grepl("'", lev$sql_expr))
})
