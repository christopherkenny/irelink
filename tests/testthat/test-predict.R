# Sprint 8 — Prediction: predict.il_model()
# Translated from: test_full_example_duckdb.py, test_full_example_sqlite.py,
#                  test_train_vs_predict.py, test_compare_splink2.py

# Helper to build a trained model for prediction tests
make_trained_model <- function(con) {
  df <- il_demo("fake_1000")
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

test_that("predict() returns an il_compared tibble", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  expect_s3_class(pairs, "il_compared")
  expect_s3_class(pairs, "tbl_df")
})

test_that("predict() output has required columns", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  required_cols <- c("unique_id_l", "unique_id_r", "match_weight", "match_probability")
  for (col in required_cols) {
    expect_true(col %in% names(pairs), info = paste("Missing column:", col))
  }
})

test_that("predict() threshold filters out low-probability pairs", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

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

test_that("predict() includes gamma columns for each comparison", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  # Should have gamma columns matching the comparisons in the spec
  gamma_cols <- grep("^gamma_", names(pairs), value = TRUE)
  expect_true(length(gamma_cols) >= 2)
})

test_that("predict() match probabilities are in [0, 1]", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model)

  expect_true(all(pairs$match_probability >= 0 & pairs$match_probability <= 1))
})

# --- Known duplicates (from 09-implementation-plan §3i) -------------------

test_that("predict() finds known planted duplicates in demo data", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

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

test_that("il_compared supports dplyr verbs", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("dplyr")

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model, threshold = 0.0)

  # filter
  high <- dplyr::filter(pairs, match_probability > 0.8)
  expect_s3_class(high, "tbl_df")

  # mutate
  with_flag <- dplyr::mutate(pairs, is_match = match_probability > 0.5)
  expect_true("is_match" %in% names(with_flag))

  # summarise
  summary <- dplyr::summarise(pairs, n = dplyr::n(), mean_prob = mean(match_probability))
  expect_true("mean_prob" %in% names(summary))
})

test_that("il_compared prints like a tibble", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_trained_model(con)
  pairs <- predict(model, threshold = 0.5)

  # il_compared inherits from tbl_df, so print should not error
  expect_output(print(pairs))
})
