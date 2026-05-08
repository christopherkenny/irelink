test_that('il_estimate_em respects max_iterations', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)

  # With 1 iteration, should still return a valid model
  model_1 <- il_estimate_em(model, block_on(city), max_iterations = 1L)
  expect_true(model_1$trained)
  # History should have exactly 1 entry (1 iteration)
  expect_length(model_1$params$history, 1L)
})

test_that('il_estimate_em fix_prior=FALSE updates prior', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)

  original_prior <- model$params$prior %||% 0.05
  model2 <- il_estimate_em(model, block_on(city), fix_prior = FALSE)
  # Prior should have changed
  expect_false(identical(model2$params$prior, original_prior))
})

test_that('il_estimate_em derive_prior=TRUE stores derived prior', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)

  model2 <- il_estimate_em(model, block_on(city), derive_prior = TRUE)
  expect_true(!is.null(model2$params$prior))
  expect_true(model2$params$prior > 0 && model2$params$prior < 1)
})

test_that('il_estimate_em validates max_iterations', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)

  expect_error(il_estimate_em(model, block_on(city), max_iterations = 0L))
  expect_error(il_estimate_em(model, block_on(city), max_iterations = -1L))
  expect_error(il_estimate_em(model, block_on(city), max_iterations = 'ten'))
})

test_that('il_estimate_em validates blocking and convergence before training', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)

  expect_error(
    il_estimate_em(model, list(columns = 'city')),
    'blocking'
  )
  expect_error(
    il_estimate_em(model, block_on(city), convergence = 0),
    'convergence'
  )
  expect_error(
    il_estimate_em(model, block_on(city), convergence = Inf),
    'convergence'
  )
})
