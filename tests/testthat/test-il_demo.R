# Sprint 4 — Bundled datasets

test_that('fake_1000 returns a tibble', {
  skip_if_sprint_lt(4)
  expect_s3_class(fake_1000, 'tbl_df')
})

test_that('fake_1000 has expected columns', {
  skip_if_sprint_lt(4)
  expected_cols <- c(
    'unique_id', 'first_name', 'surname', 'dob', 'city',
    'email', 'cluster'
  )
  for (col in expected_cols) {
    expect_true(col %in% names(fake_1000), info = paste('Missing column:', col))
  }
})

test_that('fake_1000 has 1000 rows and 181 clusters', {
  skip_if_sprint_lt(4)
  expect_equal(nrow(fake_1000), 1000)
  expect_equal(length(unique(fake_1000$cluster)), 181)
})

test_that('fake_1000_labels returns pairwise labels', {
  skip_if_sprint_lt(4)
  expect_s3_class(fake_1000_labels, 'tbl_df')
  expect_true('unique_id_l' %in% names(fake_1000_labels))
  expect_true('unique_id_r' %in% names(fake_1000_labels))
  expect_true('clerical_match_score' %in% names(fake_1000_labels))
  expect_equal(nrow(fake_1000_labels), 3176)
})

test_that('febrl4a returns FEBRL original records', {
  skip_if_sprint_lt(4)
  expect_s3_class(febrl4a, 'tbl_df')
  expect_equal(nrow(febrl4a), 5000)
  expect_true('rec_id' %in% names(febrl4a))
  expect_true('given_name' %in% names(febrl4a))
})

test_that('febrl4b returns FEBRL duplicate records', {
  skip_if_sprint_lt(4)
  expect_s3_class(febrl4b, 'tbl_df')
  expect_equal(nrow(febrl4b), 5000)
  expect_true(all(grepl('dup', febrl4b$rec_id)))
})

test_that('fake_20 includes cluster column', {
  skip_if_sprint_lt(4)
  expect_true('cluster' %in% names(fake_20))
  expect_equal(length(unique(fake_20$cluster)), 5)
})

test_that('fake_20 has no unique_id column', {
  skip_if_sprint_lt(4)
  expect_false('unique_id' %in% names(fake_20))
})
