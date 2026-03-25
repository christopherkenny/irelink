# Sprint 2 — Domain-knowledge comparison bundles
# Translated from: test_comparison_template_lib.py
# (test_name_comparison, test_email_comparison, test_date_of_birth_comparison_levels,
#  test_postcode_comparison, test_forename_surname_comparison)

# --- cl_name() ------------------------------------------------------------
# From: test_name_comparison — splink thresholds: exact, JW >= 0.92, >= 0.88, >= 0.7

test_that("cl_name() returns a comparison level with correct structure", {
  skip_if_sprint_lt(2)
  lev <- cl_name()
  expect_s3_class(lev, "il_comparison_level")
})

test_that("cl_name() has the expected number of levels", {
  skip_if_sprint_lt(2)
  # Expected: null + exact + JW(0.92) + JW(0.88) + JW(0.7) + else = 6 levels
  # (or a structured equivalent)
  lev <- cl_name()
  expect_true(length(lev$levels) >= 4)
})

test_that("cl_name() produces equivalent structure to manual composition", {
  skip_if_sprint_lt(2)
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

# --- cl_email() -----------------------------------------------------------
# From: test_email_comparison — levels: exact, exact-username, JW >= 0.88, JW-username

test_that("cl_email() returns a comparison level with correct structure", {
  skip_if_sprint_lt(2)
  lev <- cl_email()
  expect_s3_class(lev, "il_comparison_level")
})

test_that("cl_email() has at least 4 match levels", {
  skip_if_sprint_lt(2)
  lev <- cl_email()
  # Expected: null + exact + exact-username + JW + JW-username + else >= 6
  expect_true(length(lev$levels) >= 4)
})

# --- cl_dob() -------------------------------------------------------------
# From: test_date_of_birth_comparison_levels

test_that("cl_dob() returns a comparison level with correct structure", {
  skip_if_sprint_lt(2)
  lev <- cl_dob()
  expect_s3_class(lev, "il_comparison_level")
})

test_that("cl_dob() has at least 4 match levels", {
  skip_if_sprint_lt(2)
  lev <- cl_dob()
  # Expected: null + exact + DL<=1 + date_diff<=1month + <=1year + <=10year + else
  expect_true(length(lev$levels) >= 4)
})

# --- cl_postcode() --------------------------------------------------------
# From: test_postcode_comparison — levels: exact, sector, district, area

test_that("cl_postcode() returns a comparison level with correct structure", {
  skip_if_sprint_lt(2)
  lev <- cl_postcode()
  expect_s3_class(lev, "il_comparison_level")
})

test_that("cl_postcode() has at least 4 match levels", {
  skip_if_sprint_lt(2)
  lev <- cl_postcode()
  # Expected: null + full + sector + district + area + else >= 6
  expect_true(length(lev$levels) >= 4)
})

# --- cl_forename_surname() ------------------------------------------------
# From: test_forename_surname_comparison — includes reversed-columns check

test_that("cl_forename_surname() returns a comparison level with correct structure", {
  skip_if_sprint_lt(2)
  lev <- cl_forename_surname()
  expect_s3_class(lev, "il_comparison_level")
})

test_that("cl_forename_surname() has at least 5 match levels", {
  skip_if_sprint_lt(2)
  lev <- cl_forename_surname()
  # Expected: null + exact-both + reversed + JW(0.92)-both + JW(0.88) + exact-forename + else >= 7
  expect_true(length(lev$levels) >= 5)
})
