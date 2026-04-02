test_that('il_suggest_blocking returns ranked rules', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  result <- il_suggest_blocking(df, con = con)
  expect_true(is.data.frame(result))
  expect_true(nrow(result) > 0)
  expect_true(all(c(
    'rule', 'n_distinct', 'coverage', 'n_pairs',
    'pct_of_cartesian', 'score'
  ) %in% names(result)))
  # Should be sorted by score descending
  expect_true(all(diff(result$score) <= 0))
})

test_that('il_suggest_blocking with max_depth = 2', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  result1 <- il_suggest_blocking(df, con = con, max_depth = 1)
  result2 <- il_suggest_blocking(df, con = con, max_depth = 2)
  expect_true(nrow(result2) > nrow(result1))
  # Two-column combos should have " & " in rule name
  expect_true(any(grepl(' & ', result2$rule)))
})

test_that('il_suggest_blocking with specific columns', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  result <- il_suggest_blocking(df,
    columns = c('first_name', 'surname'),
    con = con
  )
  expect_equal(nrow(result), 2)
  expect_true(all(result$rule %in% c('first_name', 'surname')))
})

test_that('il_find_blocking_below filters by max_pairs', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  result <- il_find_blocking_below(df, max_pairs = 5000, con = con)
  if (nrow(result) > 0) {
    expect_true(all(result$n_pairs <= 5000))
  }
})

test_that('block_from_labels computes recall per column', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  # Adapt fake_1000_labels to the standard format
  labels <- data.frame(
    unique_id_l = fake_1000_labels$unique_id_l,
    unique_id_r = fake_1000_labels$unique_id_r,
    is_match = as.integer(fake_1000_labels$clerical_match_score >= 0.5)
  )
  result <- block_from_labels(df, labels, con = con)
  expect_true(is.data.frame(result))
  expect_true(all(c('column', 'recall', 'n_matches_caught') %in% names(result)))
  expect_true(all(result$recall >= 0 & result$recall <= 1))
  # Should be sorted by recall descending
  expect_true(all(diff(result$recall) <= 0))
})
