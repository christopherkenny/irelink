# Pipeline integration tests — full end-to-end workflows
# From: 09-implementation-plan §6b (tidyverse integration)
# These verify that irelink objects compose cleanly with the tidyverse.

# --- Full pipe chain (Sprint 8 MVP) --------------------------------------

test_that("full pipe chain: spec → model → predict works end-to-end", {
  skip_if_sprint_lt(8)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  df <- il_demo("fake_1000")

  pairs <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_compare(city, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(surname) |>
    il_model(df, spec = _, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name, surname)) |>
    il_estimate_em(block_on(dob)) |>
    predict(threshold = 0.5)

  expect_s3_class(pairs, "il_compared")
  expect_true(nrow(pairs) > 0)
})

# --- Full pipe chain through clustering (Sprint 9) -----------------------

test_that("full pipe chain through clustering assigns cluster IDs", {
  skip_if_sprint_lt(9)
  skip_if_not_installed("RSQLite")

  con <- test_con()
  withr::defer(test_discon(con))

  df <- il_demo("fake_1000")

  clusters <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(first_name) |>
    il_model(df, spec = _, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name, surname)) |>
    predict(threshold = 0.5) |>
    il_cluster()

  expect_true("cluster_id" %in% names(clusters))
})

# --- ggplot2 from tidy data (Sprint 10) -----------------------------------

test_that("il_weights() data can be used directly with ggplot2", {
  skip_if_sprint_lt(10)
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("ggplot2")

  con <- test_con()
  withr::defer(test_discon(con))

  df <- il_demo("fake_1000")

  model <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name) |>
    il_model(df, spec = _, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  wt <- il_weights(model)

  # il_weights() returns tidy data that ggplot2 can consume directly
  p <- ggplot2::ggplot(wt, ggplot2::aes(x = level, y = weight)) +
    ggplot2::geom_col()

  expect_s3_class(p, "ggplot")
})
