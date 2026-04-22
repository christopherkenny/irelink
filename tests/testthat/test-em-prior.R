test_that('blocking prior helpers reverse one another', {
  prior <- 0.001
  deactivated <- c(TRUE, FALSE)
  m_list <- list(c(0.1, 0.9), c(0.8, 0.2))
  u_list <- list(c(0.9, 0.1), c(0.7, 0.3))
  levels_per_comp <- c(2L, 2L)

  adjusted <- adjust_prior_for_blocking(
    prior, deactivated, m_list, u_list, levels_per_comp
  )
  reversed <- reverse_blocking_adjusted_prior(
    adjusted, deactivated, m_list, u_list, levels_per_comp
  )

  expect_equal(reversed, clamp_probability(prior))
})

test_that('il_estimate_em stores the global prior after blocked training', {
  con <- test_con()
  withr::defer(test_discon(con))

  spec <- il_spec() |>
    il_compare(first_name, cl_name()) |>
    il_compare(surname, cl_name()) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname)

  model <- il_model(fake_1000, spec = spec, con = con) |>
    il_estimate_prior(block_on(first_name, surname, dob), recall = 0.8) |>
    il_estimate_u(max_pairs = 1e5)

  prior_before <- model$params$prior
  trained <- il_estimate_em(model, block_on(surname), max_iterations = 5L)

  expect_gt(trained$params$prior, 0)
  expect_lt(trained$params$prior, 0.05)
  expect_lt(trained$params$prior, 50 * prior_before)
})
