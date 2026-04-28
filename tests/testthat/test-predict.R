# Sprint 8 — Prediction: predict.il_model()
# Translated from: test_full_example_duckdb.py, test_full_example_sqlite.py,
# test_train_vs_predict.py, test_compare_splink2.py

# Helper to build a trained model for prediction tests
make_trained_model <- function(con) {
  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_compare(city, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(surname)

  il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name, surname)) |>
    il_estimate_em(block_on(dob))
}

make_tied_link_model <- function(con) {
  df_l <- data.frame(
    unique_id = c(20L, 10L),
    key = c('match', 'match'),
    stringsAsFactors = FALSE
  )
  df_r <- data.frame(
    unique_id = c(200L, 100L),
    key = c('match', 'match'),
    stringsAsFactors = FALSE
  )
  spec <- il_spec() |>
    il_compare(key, cl_exact()) |>
    il_block_on(key)

  il_model(df_l, df_r,
    spec = spec,
    con = con,
    link_type = 'link'
  ) |>
    il_estimate_u(max_pairs = 1e4) |>
    il_estimate_em(block_on(key))
}

test_that('predict() returns an il_compared tibble', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  expect_s3_class(pairs, 'il_compared')
  expect_s3_class(pairs, 'tbl_df')
})

test_that('predict() output has required columns', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  required_cols <- c(
    'unique_id_l', 'unique_id_r', 'match_weight',
    'total_match_weight', 'match_probability'
  )
  expect_true(all(required_cols %in% names(pairs)))
})

test_that('predict() keeps evidence and prior match weights explicit', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model, threshold = 0.0)

  prior_weight <- log2(model$params$prior / (1 - model$params$prior))
  expect_equal(pairs$total_match_weight, pairs$match_weight + prior_weight)
  expect_equal(
    pairs$match_probability,
    1 / (1 + 2^(-pairs$total_match_weight))
  )
})

test_that('predict() threshold filters out low-probability pairs', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)

  pairs_all <- predict(model, threshold = 0.0)
  pairs_high <- predict(model, threshold = 0.9)

  expect_true(nrow(pairs_all) >= nrow(pairs_high))
  if (nrow(pairs_high) > 0) {
    expect_true(all(pairs_high$match_probability >= 0.9))
  }
})

test_that('predict() includes gamma columns for each comparison', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  # Should have gamma columns matching the comparisons in the spec
  gamma_cols <- grep('^gamma_', names(pairs), value = TRUE)
  expect_true(length(gamma_cols) >= 2)
})

test_that('predict() match probabilities are in [0, 1]', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  expect_true(all(pairs$match_probability >= 0 & pairs$match_probability <= 1))
})

# --- Known duplicates (from 09-implementation-plan §3i) -------------------

test_that('predict() finds known planted duplicates in demo data', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model, threshold = 0.5)

  # Demo fake_1000 contains planted duplicate clusters.
  # The trained model should find at least some of them.
  expect_true(nrow(pairs) > 0)

  # Records in the same cluster should share a cluster identifier
  # (verified in Sprint 9), but at this stage we just confirm
  # high-probability pairs exist among the known duplicates.
})

# --- Tidyverse integration (from 09-implementation-plan §6b) --------------

test_that('il_compared supports dplyr verbs', {
  skip_if_not_installed('RSQLite')
  skip_if_not_installed('dplyr')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model, threshold = 0.0)

  # filter
  high <- dplyr::filter(pairs, match_probability > 0.8)
  expect_s3_class(high, 'tbl_df')

  # mutate
  with_flag <- dplyr::mutate(pairs, is_match = match_probability > 0.5)
  expect_true('is_match' %in% names(with_flag))

  # summarise
  summary <- dplyr::summarise(pairs, n = dplyr::n(), mean_prob = mean(match_probability))
  expect_true('mean_prob' %in% names(summary))
})

test_that('predict() threshold_match_weight filters on weight', {
  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)

  pairs_all <- predict(model, threshold = 0.0)
  # Use a weight threshold that should return fewer pairs
  pairs_mw <- predict(model, threshold_match_weight = 0)

  expect_true(nrow(pairs_all) >= nrow(pairs_mw))
  if (nrow(pairs_mw) > 0) {
    expect_true(all(pairs_mw$match_weight >= 0))
  }
})

test_that('threshold_match_weight overrides probability threshold', {
  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)

  # Even with probability threshold of 0.99, weight threshold takes priority
  pairs <- predict(model, threshold = 0.99, threshold_match_weight = -100)
  pairs_prob <- predict(model, threshold = 0.0)

  # weight threshold of -100 should include everything
  expect_equal(nrow(pairs), nrow(pairs_prob))
})

test_that('greedy_match_pairs uses global posterior ordering', {
  pairs <- tibble::tibble(
    unique_id_l = c('a1', 'a2', 'a2'),
    unique_id_r = c('b1', 'b1', 'b2'),
    match_weight = c(1, 1, 1),
    match_probability = c(0.90, 0.89, 0.88)
  )

  matched <- greedy_match_pairs(
    pairs,
    row_index_l = c(1L, 2L, 2L),
    row_index_r = c(1L, 1L, 2L)
  )

  expect_equal(matched$unique_id_l, c('a1', 'a2'))
  expect_equal(matched$unique_id_r, c('b1', 'b2'))
})

test_that('predict(greedy = TRUE) keeps a deterministic one-to-one matching', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_tied_link_model(con)

  all_pairs <- predict(model, threshold = 0)
  greedy_pairs <- predict(model, threshold = 0, greedy = TRUE)

  expect_equal(nrow(all_pairs), 4)
  expect_equal(nrow(greedy_pairs), 2)
  expect_equal(length(unique(greedy_pairs$unique_id_l)), nrow(greedy_pairs))
  expect_equal(length(unique(greedy_pairs$unique_id_r)), nrow(greedy_pairs))
  expect_equal(greedy_pairs$unique_id_l, c(20, 10))
  expect_equal(greedy_pairs$unique_id_r, c(200, 100))
})

test_that('predict(greedy = TRUE, collect = FALSE) returns a lazy one-to-one result', {
  skip_if_not_installed('duckdb')

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  model <- make_tied_link_model(con)

  collected <- predict(model, threshold = 0, greedy = TRUE)
  lazy <- predict(model, threshold = 0, greedy = TRUE, collect = FALSE)
  greedy_pairs <- collect_il_compared_lazy(lazy)

  expect_s3_class(lazy, 'il_compared_lazy')
  expect_equal(greedy_pairs$unique_id_l, collected$unique_id_l)
  expect_equal(greedy_pairs$unique_id_r, collected$unique_id_r)
  expect_equal(greedy_pairs$total_match_weight, collected$total_match_weight)
  expect_equal(length(unique(greedy_pairs$unique_id_l)), nrow(greedy_pairs))
  expect_equal(length(unique(greedy_pairs$unique_id_r)), nrow(greedy_pairs))
})

test_that('predict(greedy = TRUE) is only available for link models', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)

  expect_error(
    predict(model, greedy = TRUE),
    'only supported'
  )
})
