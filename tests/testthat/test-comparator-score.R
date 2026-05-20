test_that('il_comparator_score computes batch similarity (R path)', {
  df <- data.frame(
    name_l = c('John', 'Jane', 'Bob'),
    name_r = c('Jon', 'Janet', 'Bobby'),
    stringsAsFactors = FALSE
  )
  result <- il_comparator_score(df, name_l, name_r)
  expect_s3_class(result, 'il_comparator_score')
  expect_equal(nrow(result), 3)
  expect_true('jaro_winkler' %in% names(result))
  expect_true('levenshtein' %in% names(result))
  expect_true(all(result$jaro_winkler >= 0 & result$jaro_winkler <= 1))
})

test_that('il_comparator_score handles NA values', {
  df <- data.frame(
    name_l = c('John', NA, 'Bob'),
    name_r = c('Jon', 'Janet', NA),
    stringsAsFactors = FALSE
  )
  result <- il_comparator_score(df, name_l, name_r)
  expect_equal(nrow(result), 1)
})

test_that('il_comparator_score SQL path works on DuckDB', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- data.frame(
    name_l = c('John', 'Jane', 'Bob'),
    name_r = c('Jon', 'Janet', 'Bobby'),
    stringsAsFactors = FALSE
  )
  result <- il_comparator_score(df, name_l, name_r, con = con)
  expect_s3_class(result, 'il_comparator_score')
  expect_equal(nrow(result), 3)
})

test_that('il_comparator_score DuckDB metrics stay on the 0-1 scale', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- data.frame(name_l = 'John', name_r = 'Jon', stringsAsFactors = FALSE)
  result <- il_comparator_score(df, name_l, name_r, con = con)

  expect_gt(result$jaro_winkler[[1]], 0.9)
  expect_gt(result$jaro[[1]], 0.9)
})

test_that('il_comparator_score SQL path quotes non-syntactic column names', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- data.frame(
    check.names = FALSE,
    'first name' = 'John',
    'other name' = 'Jon'
  )
  result <- il_comparator_score(df, `first name`, `other name`, con = con)

  expect_equal(nrow(result), 1L)
  expect_true(all(c('first name', 'other name') %in% names(result)))
  expect_gt(result$jaro_winkler[[1]], 0.9)
})

test_that('il_comparator_threshold_chart returns ggplot', {
  df <- data.frame(
    name_l = c('John', 'Jane', 'Bob', 'Alice'),
    name_r = c('Jon', 'Janet', 'Bobby', 'Alison'),
    stringsAsFactors = FALSE
  )
  p <- il_comparator_threshold_chart(
    df,
    name_l,
    name_r,
    similarity_threshold = 0.8
  )
  expect_s3_class(p, 'ggplot')
})

test_that('il_phonetic_chart returns ggplot', {
  df <- data.frame(
    name_l = c('Smith', 'Jones', 'Brown'),
    name_r = c('Smyth', 'Jonez', 'Browne'),
    stringsAsFactors = FALSE
  )
  p <- il_phonetic_chart(df, name_l, name_r)
  expect_s3_class(p, 'ggplot')
})

test_that('il_phonetic_chart SQL path quotes non-syntactic column names', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- data.frame(
    check.names = FALSE,
    'first name' = c('Smith', 'Jones'),
    'other name' = c('Smyth', 'Jonez')
  )
  p <- il_phonetic_chart(df, `first name`, `other name`, con = con)

  expect_s3_class(p, 'ggplot')
})
