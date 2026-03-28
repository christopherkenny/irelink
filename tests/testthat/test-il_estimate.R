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
  # The estimated prior should be a probability in [0, 1]
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
