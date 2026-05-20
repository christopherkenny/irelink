# Sprint 5 — Exploration: il_count_pairs()
# Translated from: test_analyse_blocking.py, test_total_comparison_count.py

test_that('il_count_pairs() returns accurate pair count for dedupe', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # 4 records: John Smith, Mary Jones, Jane Taylor, John Brown
  df <- data.frame(
    unique_id = 1:4,
    first_name = c('John', 'Mary', 'Jane', 'John'),
    surname = c('Smith', 'Jones', 'Taylor', 'Brown')
  )

  # Cartesian for dedupe: n(n-1)/2 = 4*3/2 = 6
  result <- il_count_pairs(df, con = con)
  expect_s3_class(result, 'tbl_df')
  expect_true('n_pairs' %in% names(result))
})

test_that('il_count_pairs() with blocking reduces pair count', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_analyse_blocking.py — 4 rows, block_on("first_name")
  # Two Johns: only 1 pair blocked
  df <- data.frame(
    unique_id = 1:4,
    first_name = c('John', 'Mary', 'Jane', 'John'),
    surname = c('Smith', 'Jones', 'Taylor', 'Brown')
  )

  result <- il_count_pairs(df, block_on(first_name), con = con)
  first_name_pairs <- result$n_pairs[1]

  # Only 2 Johns -> C(2,2) = 1 pair
  expect_equal(first_name_pairs, 1)
})

test_that('il_count_pairs() cartesian dedupe is n*(n-1)/2', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_total_comparison_count.py
  # 5 records -> 5*4/2 = 10 pairs
  df <- data.frame(
    unique_id = 1:5,
    name = paste0('person_', 1:5)
  )

  result <- il_count_pairs(df, con = con)
  expect_equal(result$n_pairs[1], 10)
})

test_that("il_count_pairs() for link_type='link' computes cross-product", {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_total_comparison_count.py::test_calculate_cartesian_link_only
  # 2 records * 3 records = 6 pairs
  df1 <- data.frame(unique_id = 1:2, name = c('A', 'B'))
  df2 <- data.frame(unique_id = 3:5, name = c('C', 'D', 'E'))

  result <- il_count_pairs(df1, df2, con = con, link_type = 'link')
  expect_equal(result$n_pairs[1], 6)
})

test_that('il_count_pairs() with multiple blocking rules reports each', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('John', 'Mary', 'Jane', 'John'),
    surname = c('Smith', 'Jones', 'Taylor', 'Brown')
  )

  result <- il_count_pairs(
    df,
    block_on(first_name),
    block_on(surname),
    con = con
  )

  # Should report pair counts for each blocking rule
  expect_true(nrow(result) >= 2)
})
