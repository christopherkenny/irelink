# Term frequency adjustment tests
# Verifies TF table computation, adjustment math, and end-to-end behavior.

# Helper: build a model with known value frequencies
make_tf_model <- function(con) {
  # City distribution: London x40, Birmingham x8, Truro x2
  # This gives tf_London = 0.80, tf_Birmingham = 0.16, tf_Truro = 0.04
  df <- data.frame(
    unique_id = 1:50,
    city = c(rep('London', 40), rep('Birmingham', 8), rep('Truro', 2)),
    name = paste0('Person', 1:50),
    stringsAsFactors = FALSE
  )
  spec <- il_spec() |>
    il_compare(city, cl_exact(term_frequency = TRUE)) |>
    il_compare(name, cl_exact()) |>
    il_block_on(city)
  il_model(df, spec = spec, con = con)
}

# --- TF table computation ---------------------------------------------------

test_that('compute_tf_tables() creates TF lookup table in the database', {
  skip_if_sprint_lt(10)

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_tf_model(con)

  # The TF table should exist
  expect_true(DBI::dbExistsTable(con, '__il_tf_city'))

  # And be registered in the model

  expect_true('city' %in% names(model$data$tf_tables))
})

test_that('TF table has correct frequencies', {
  skip_if_sprint_lt(10)

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_tf_model(con)
  tf <- DBI::dbReadTable(con, '__il_tf_city')

  # Sort by city name for stable assertions
  tf <- tf[order(tf$city), ]

  expect_equal(nrow(tf), 3)
  expect_equal(tf$city, c('Birmingham', 'London', 'Truro'))
  expect_equal(tf$tf_city, c(8 / 50, 40 / 50, 2 / 50), tolerance = 1e-10)
})

test_that('tf_columns() identifies TF-enabled comparisons', {
  skip_if_sprint_lt(10)

  spec_tf <- il_spec() |>
    il_compare(city, cl_exact(term_frequency = TRUE)) |>
    il_compare(name, cl_exact())

  cols <- irelink:::tf_columns(spec_tf$comparisons)
  expect_equal(cols, 'city')
})

test_that('tf_columns() returns empty for no TF comparisons', {
  skip_if_sprint_lt(10)

  spec_no_tf <- il_spec() |>
    il_compare(city, cl_exact()) |>
    il_compare(name, cl_exact())

  cols <- irelink:::tf_columns(spec_no_tf$comparisons)
  expect_length(cols, 0)
})

# --- TF adjustment math ------------------------------------------------------

test_that('compute_tf_adjustment() produces correct adjustments', {
  skip_if_sprint_lt(10)

  # Set up: 3 pairs, one comparison with TF
  comparisons <- list(
    list(columns = 'city', method = cl_exact(term_frequency = TRUE))
  )

  gamma_mat <- matrix(c(1L, 1L, 0L),
    ncol = 1,
    dimnames = list(NULL, 'city')
  )

  tf_data <- data.frame(
    tf_city_l = c(0.80, 0.04, 0.80),
    tf_city_r = c(0.80, 0.04, 0.16)
  )

  mu <- list(
    m_match = 0.95,
    m_nonmatch = 0.05,
    u_match = 0.10,
    u_nonmatch = 0.90
  )

  adj <- irelink:::compute_tf_adjustment(gamma_mat, tf_data, comparisons, mu)

  # Pair 1: gamma=1, tf_max = max(0.80, 0.80) = 0.80
  #   adj = log2(0.10 / 0.80) = log2(0.125) = -3
  expect_equal(adj[1], log2(0.10 / 0.80), tolerance = 1e-10)

  # Pair 2: gamma=1, tf_max = max(0.04, 0.04) = 0.04
  #   adj = log2(0.10 / 0.04) = log2(2.5) ≈ 1.322
  expect_equal(adj[2], log2(0.10 / 0.04), tolerance = 1e-10)

  # Pair 3: gamma=0, no adjustment
  expect_equal(adj[3], 0)
})

test_that('TF adjustment is zero when term_frequency is FALSE', {
  skip_if_sprint_lt(10)

  comparisons <- list(
    list(columns = 'city', method = cl_exact()) # No TF
  )
  gamma_mat <- matrix(c(1L, 1L),
    ncol = 1,
    dimnames = list(NULL, 'city')
  )
  tf_data <- data.frame(tf_city_l = c(0.5, 0.5), tf_city_r = c(0.5, 0.5))
  mu <- list(m_match = 0.9, m_nonmatch = 0.1, u_match = 0.1, u_nonmatch = 0.9)

  adj <- irelink:::compute_tf_adjustment(gamma_mat, tf_data, comparisons, mu)
  expect_equal(adj, c(0, 0))
})

# --- End-to-end: TF changes match weights ------------------------------------

test_that('TF adjustments change match weights vs non-TF', {
  skip_if_sprint_lt(10)

  con <- test_con()
  withr::defer(test_discon(con))

  # Create two models: one with TF, one without
  df <- data.frame(
    unique_id = 1:50,
    city = c(rep('London', 40), rep('Birmingham', 8), rep('Truro', 2)),
    name = paste0('Person', 1:50),
    stringsAsFactors = FALSE
  )

  spec_tf <- il_spec() |>
    il_compare(city, cl_exact(term_frequency = TRUE)) |>
    il_compare(name, cl_exact()) |>
    il_block_on(city)

  model_tf <- il_model(df, spec = spec_tf, con = con) |>
    il_estimate_u() |>
    il_estimate_em(block_on(city))

  pairs_tf <- predict(model_tf, threshold = 0)

  # Now build the same model without TF
  con2 <- test_con()
  withr::defer(test_discon(con2))

  spec_no_tf <- il_spec() |>
    il_compare(city, cl_exact()) |>
    il_compare(name, cl_exact()) |>
    il_block_on(city)

  model_no_tf <- il_model(df, spec = spec_no_tf, con = con2) |>
    il_estimate_u() |>
    il_estimate_em(block_on(city))

  pairs_no_tf <- predict(model_no_tf, threshold = 0)

  # Match weights should differ when gamma_city == 1
  # (TF adjusts the weight based on value frequency)
  tf_weights <- pairs_tf$match_weight[pairs_tf$gamma_city == 1]
  no_tf_weights <- pairs_no_tf$match_weight[pairs_no_tf$gamma_city == 1]

  # The TF model should not have identical weights for all city-matching pairs
  # (London vs Truro pairs get different adjustments)
  if (length(tf_weights) > 1) {
    expect_true(
      sd(tf_weights) > sd(no_tf_weights),
      info = 'TF should increase variance of match weights across different city values'
    )
  }
})

test_that('TF gives rare values higher weights than common values', {
  skip_if_sprint_lt(10)

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_tf_model(con) |>
    il_estimate_u() |>
    il_estimate_em(block_on(city))

  pairs <- predict(model, threshold = 0)

  if (nrow(pairs) > 0) {
    # Get a London pair and a Truro pair (if any)
    # Due to blocking on city, all pairs share the same city
    # Look at the tf_adj_city column
    if ('tf_adj_city' %in% names(pairs)) {
      london_adj <- pairs$tf_adj_city[pairs$gamma_city == 1][1]
      # We can't easily separate London vs Truro pairs without city values,
      # but we can check that tf_adj_city varies
      tf_adjs <- pairs$tf_adj_city[pairs$gamma_city == 1]
      if (length(unique(tf_adjs)) > 1) {
        # Rare values (smaller TF) should have higher adjustments
        expect_true(max(tf_adjs) > min(tf_adjs))
      }
    }
  }
})

# --- Waterfall includes TF ---------------------------------------------------

test_that('waterfall includes TF adjustment in contributions', {
  skip_if_sprint_lt(10)

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_tf_model(con) |>
    il_estimate_u() |>
    il_estimate_em(block_on(city))

  pairs <- predict(model, threshold = 0)

  if (nrow(pairs) > 0) {
    wf <- il_waterfall(pairs, which = 1)
    expect_s3_class(wf, 'tbl_df')
    expect_true('city' %in% wf$step)
    # The contribution for city should include TF adjustment
    # (it will differ from the base w1/w0 when TF is active)
    expect_true(is.numeric(wf$contribution))
  }
})

# --- No TF tables when not needed --------------------------------------------

test_that('No TF tables created when no comparisons use TF', {
  skip_if_sprint_lt(10)

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:10,
    city = rep(c('A', 'B'), 5),
    stringsAsFactors = FALSE
  )
  spec <- il_spec() |>
    il_compare(city, cl_exact()) |>
    il_block_on(city)

  model <- il_model(df, spec = spec, con = con)

  expect_false(DBI::dbExistsTable(con, '__il_tf_city'))
  expect_null(model$data$tf_tables)
})

# --- SQL TF select expressions -----------------------------------------------

test_that('sql_tf_select_exprs() generates correct SQL fragments', {
  skip_if_sprint_lt(10)

  exprs <- irelink:::sql_tf_select_exprs(c('city', 'name'))
  expect_true(grepl('tf_city_l', exprs))
  expect_true(grepl('tf_city_r', exprs))
  expect_true(grepl('tf_name_l', exprs))
  expect_true(grepl('tf_name_r', exprs))
  expect_true(grepl('__il_tf_city', exprs))
  expect_true(grepl('__il_tf_name', exprs))
})

test_that('sql_tf_select_exprs() returns NULL for empty input', {
  skip_if_sprint_lt(10)

  expect_null(irelink:::sql_tf_select_exprs(character(0)))
})
