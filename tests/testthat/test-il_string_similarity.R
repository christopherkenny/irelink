# Sprint 4 — String similarity: il_string_similarity()
# No direct splink equivalent test — this is an irelink utility.
# Tests verify correctness against known string-pair scores.

test_that("il_string_similarity() returns a tibble", {
  skip_if_sprint_lt(4)
  result <- il_string_similarity("Robert", "Robt")
  expect_s3_class(result, "tbl_df")
})

test_that("il_string_similarity() has expected metric columns", {
  skip_if_sprint_lt(4)
  result <- il_string_similarity("hello", "helo")
  expected_cols <- c("jaro_winkler", "jaro", "levenshtein", "jaccard", "cosine")
  for (col in expected_cols) {
    expect_true(col %in% names(result), info = paste("Missing column:", col))
  }
})

test_that("identical strings return 1.0 for similarity metrics", {
  skip_if_sprint_lt(4)
  result <- il_string_similarity("hello", "hello")
  expect_equal(result$jaro_winkler, 1.0)
  expect_equal(result$jaro, 1.0)
  expect_equal(result$levenshtein, 0L) # distance, not similarity
})

test_that("known string pairs produce expected Jaro-Winkler scores", {
  skip_if_sprint_lt(4)
  # "Robert" vs "Robt" — well-known JW test case
  result <- il_string_similarity("Robert", "Robt")
  expect_true(result$jaro_winkler > 0.85)
  expect_true(result$jaro_winkler < 1.0)
})

test_that("completely different strings produce low similarity", {
  skip_if_sprint_lt(4)
  result <- il_string_similarity("abc", "xyz")
  expect_true(result$jaro_winkler < 0.5)
})

test_that("empty strings are handled gracefully", {
  skip_if_sprint_lt(4)
  result <- il_string_similarity("", "hello")
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)
})

test_that("NA input is handled gracefully", {
  skip_if_sprint_lt(4)
  result <- il_string_similarity(NA_character_, "hello")
  expect_s3_class(result, "tbl_df")
  # NA inputs should produce NA scores
  expect_true(is.na(result$jaro_winkler))
})

test_that("levenshtein distances match known values", {
  skip_if_sprint_lt(4)
  # "harry" vs "barry" — distance 1
  result <- il_string_similarity("harry", "barry")
  expect_equal(result$levenshtein, 1L)

  # "harry" vs "gary" — distance 2
  result2 <- il_string_similarity("harry", "gary")
  expect_equal(result2$levenshtein, 2L)
})
