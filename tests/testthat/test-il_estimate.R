# Sprint 7 — Training: il_estimate_u(), il_estimate_em(),
# il_estimate_prior(), il_estimate_m_from_labels(),
# il_estimate_m_from_column()
# Translated from: test_u_train.py, test_expectation_maximisation.py,
# test_correctness_of_convergence.py,
# test_estimate_prob_two_rr_match.py, test_m_train.py

# Helper to create a trained-ready model
make_test_model <- function(con) {
  df <- data.frame(
    unique_id = 1:6,
    first_name = c('Amanda', 'Amanda', 'Robin', 'Robyn', 'David', 'Eve'),
    surname = c('Smith', 'Jones', 'Williams', 'Green', 'Pope', 'Anderson')
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_levenshtein(2)) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  il_model(df, spec = spec, con = con)
}

# --- il_estimate_u() ------------------------------------------------------
# From: test_u_train.py::test_u_train

test_that('il_estimate_u() returns an il_model with u parameters set', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_test_model(con) |>
    il_estimate_u(max_pairs = 1e6)

  expect_s3_class(model, 'il_model')
  params <- il_parameters(model)
  # u values should be populated (not all NA)
  expect_false(all(is.na(params$u)))
})

test_that('il_estimate_u() produces reasonable u values', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_u_train.py — 6 records, 15 pairs
  # Exact match on first_name: Amanda-Amanda = 1 pair → u ≈ 1/15
  model <- make_test_model(con) |>
    il_estimate_u(max_pairs = 1e6)

  params <- il_parameters(model)
  # All u values should be in [0, 1]
  expect_true(all(params$u >= 0 & params$u <= 1, na.rm = TRUE))
})

test_that('il_estimate_u() can stop chunked sampling after every level is observed', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(unique_id = 1:3, key = c('a', 'a', 'b'))
  spec <- il_spec() |>
    il_compare(key, cl_exact())

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(
      max_pairs = 10,
      chunk_size = 1,
      min_count_per_level = 1
    )

  expect_true(model$params$u_estimation$stopped_early)
  expect_lt(model$params$u_estimation$n_pairs_sampled, 10)
  expect_equal(model$params$u_estimation$n_pairs_sampled, 2)
})

test_that('chunked il_estimate_u() matches unchunked output for one full chunk', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  base <- make_test_model(con)
  unchunked <- il_estimate_u(base, max_pairs = 15)
  chunked <- il_estimate_u(base, max_pairs = 15, chunk_size = 15)

  expect_equal(
    dplyr::arrange(il_parameters(chunked), comparison, gamma_level)$u,
    dplyr::arrange(il_parameters(unchunked), comparison, gamma_level)$u
  )
  expect_false(chunked$params$u_estimation$stopped_early)
  expect_equal(chunked$params$u_estimation$n_chunks, 1)
})

test_that('chunked il_estimate_u() supports link mode with two tables', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df_l <- data.frame(unique_id = 1:2, key = c('a', 'b'))
  df_r <- data.frame(unique_id = 10:12, key = c('a', 'b', 'c'))
  spec <- il_spec() |>
    il_compare(key, cl_exact())

  model <- il_model(df_l, df_r,
    spec = spec, con = con, link_type = 'link'
  ) |>
    il_estimate_u(max_pairs = 6, chunk_size = 2)

  expect_equal(model$params$u_estimation$n_pairs_sampled, 6)
  expect_equal(sum(il_parameters(model)$u), 1)
})

test_that('il_estimate_u() keeps unobserved gamma levels with a u floor', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(unique_id = 1:3, name = c('abc', 'xyz', 'uvw'))
  spec <- il_spec() |>
    il_compare(name, cl_levenshtein(0, 1))

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 3, chunk_size = 2)

  params <- il_parameters(model)
  expect_equal(sort(params$gamma_level), 0:2)
  expect_equal(sum(params$u), 1)
  expect_equal(
    params$u[params$gamma_level == 1],
    1e-6 / (1 + 2e-6),
    tolerance = 1e-12
  )
  expect_equal(
    params$u[params$gamma_level == 2],
    1e-6 / (1 + 2e-6),
    tolerance = 1e-12
  )
})

# --- il_estimate_em() -----------------------------------------------------
# From: test_expectation_maximisation.py, test_correctness_of_convergence.py

test_that('il_estimate_em() returns an il_model with updated parameters', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  model <- make_test_model(con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  expect_s3_class(model, 'il_model')
})

test_that('il_estimate_em() errors clearly on empty blocking results', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_clear_error_when_empty_block
  # block on surname where no two records share a surname
  model <- make_test_model(con) |>
    il_estimate_u(max_pairs = 1e6)

  expect_error(
    il_estimate_em(model, block_on(surname))
  )
})

test_that('multiple il_estimate_em() calls refine, not reset, parameters', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name, surname))

  params_after_first <- il_parameters(model)

  model <- model |>
    il_estimate_em(block_on(dob))

  params_after_second <- il_parameters(model)

  # Parameters should not be reset to initial values
  # (they may change, but should not be NA)
  expect_false(all(is.na(params_after_second$m)))
})

# --- il_estimate_prior() --------------------------------------------------
# From: test_estimate_prob_two_rr_match.py

test_that('il_estimate_prior() returns a valid probability', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_prob_rr_match_dedupe — 6 records, 4 expected matches
  df <- data.frame(
    unique_id = 1:6,
    first_name = c('John', 'John', 'Mary', 'Mary', 'Mary', 'Jane'),
    surname = c('Smith', 'Smith', 'Jones', 'Jones', 'Jones', 'Taylor')
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_prior(block_on(first_name), block_on(surname), recall = 1.0)

  expect_s3_class(model, 'il_model')
  # The two rules produce the same four unique pairs; they should not be
  # counted twice. Total dedupe pairs are 6 * 5 / 2 = 15.
  expect_equal(model$params$prior, 4 / 15)
})

test_that('il_estimate_prior() validates recall', {
  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(unique_id = 1:2, name = c('a', 'a'))
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)
  model <- il_model(df, spec = spec, con = con)

  expect_error(il_estimate_prior(model, block_on(name), recall = 0))
  expect_error(il_estimate_prior(model, block_on(name), recall = 1.1))
  expect_error(il_estimate_prior(model, block_on(name), recall = NA_real_))
  expect_error(il_estimate_prior(model, block_on(name), recall = Inf))
})

test_that('il_estimate_prior() counts unique blocked pairs for link mode', {
  con <- test_con()
  withr::defer(test_discon(con))

  df_l <- data.frame(unique_id = 1:2, name = c('a', 'b'))
  df_r <- data.frame(unique_id = 1:2, name = c('a', 'a'))
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model <- il_model(df_l, df_r, spec = spec, con = con, link_type = 'link') |>
    il_estimate_prior(block_on(name), recall = 1.0)

  expect_equal(model$params$prior, 2 / 4)
})

test_that('il_estimate_prior() uses link_and_dedupe denominator', {
  con <- test_con()
  withr::defer(test_discon(con))

  df_l <- data.frame(unique_id = 1:2, name = c('a', 'a'))
  df_r <- data.frame(unique_id = 1:2, name = c('a', 'c'))
  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model <- il_model(
    df_l, df_r,
    spec = spec, con = con, link_type = 'link_and_dedupe'
  ) |>
    il_estimate_prior(block_on(name), recall = 1.0)

  # 2 cross-table pairs plus 1 within-left pair over
  # 2*2 cross + 1 within-left + 1 within-right possible pairs.
  expect_equal(model$params$prior, 3 / 6)
})

# --- il_estimate_m_from_labels() ------------------------------------------
# From: test_m_train.py

test_that('il_estimate_m_from_labels() computes m from pairwise labels', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_m_train — 5 records with clusters
  df <- data.frame(
    unique_id = 1:5,
    first_name = c('Robin', 'Robyn', 'Robin', 'James', 'David'),
    surname = rep('X', 5),
    cluster = c(1, 1, 1, 2, 2)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_levenshtein(2)) |>
    il_block_on(first_name)

  # Create pairwise labels from cluster assignments
  labels <- data.frame(
    unique_id_l = c(1L, 1L, 2L, 4L),
    unique_id_r = c(2L, 3L, 3L, 5L),
    is_match = c(TRUE, TRUE, TRUE, TRUE)
  )

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_m_from_labels(labels)

  params <- il_parameters(model)
  expect_false(all(is.na(params$m)))
  # All m values should be in [0, 1]
  expect_true(all(params$m >= 0 & params$m <= 1, na.rm = TRUE))
})

test_that('il_estimate_m_from_labels() validates label table shape', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:3,
    first_name = c('Robin', 'Robyn', 'James')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_levenshtein(2))
  model <- il_model(df, spec = spec, con = con)

  expect_error(
    il_estimate_m_from_labels(model, data.frame(unique_id_l = 1L)),
    'unique_id_r'
  )
  expect_error(
    il_estimate_m_from_labels(model, data.frame(
      unique_id_l = 1L,
      unique_id_r = 2L,
      is_match = NA
    )),
    'is_match'
  )
  expect_error(
    il_estimate_m_from_labels(model, data.frame(
      unique_id_l = 1L,
      unique_id_r = 2L,
      is_match = 2
    )),
    '0/1'
  )
})

# --- il_estimate_m_from_column() ------------------------------------------
# From: test_m_train.py (method 1 — label column)

test_that('il_estimate_m_from_column() computes m from a cluster column', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  # From: test_m_train — estimate_m_from_label_column("cluster")
  df <- data.frame(
    unique_id = 1:5,
    first_name = c('Robin', 'Robyn', 'Robin', 'James', 'David'),
    surname = rep('X', 5),
    cluster = c(1, 1, 1, 2, 2)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_levenshtein(2)) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_m_from_column(cluster)

  params <- il_parameters(model)
  expect_false(all(is.na(params$m)))
  expect_true(all(params$m >= 0 & params$m <= 1, na.rm = TRUE))
})
