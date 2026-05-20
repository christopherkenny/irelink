test_that('fix_u = TRUE, fix_m = FALSE is the default (current behaviour)', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  m1 <- il_estimate_em(model, block_on(surname))
  m2 <- il_estimate_em(model, block_on(surname), fix_u = TRUE, fix_m = FALSE)

  expect_equal(m1$params$comparisons$m, m2$params$comparisons$m)
  expect_equal(m1$params$comparisons$u, m2$params$comparisons$u)
})

test_that('fix_u = FALSE also updates u parameters', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  u_before <- model$params$comparisons$u

  m3 <- il_estimate_em(model, block_on(surname), fix_u = FALSE, fix_m = FALSE)
  u_after <- m3$params$comparisons$u

  expect_false(all(abs(u_after - u_before) < 1e-10))
})

test_that('fix_m = TRUE keeps m fixed', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  # First train m so it has real values
  model <- il_estimate_em(model, block_on(surname))
  m_before <- model$params$comparisons$m

  # Now re-run with fix_m = TRUE — m should not change
  m4 <- il_estimate_em(model, block_on(first_name), fix_u = FALSE, fix_m = TRUE)
  m_after <- m4$params$comparisons$m

  expect_equal(m_before, m_after)
  # But u should have changed
  expect_false(all(
    abs(m4$params$comparisons$u - model$params$comparisons$u) < 1e-10
  ))
})

test_that('both fixed errors', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)

  expect_error(
    il_estimate_em(model, block_on(surname), fix_u = TRUE, fix_m = TRUE),
    'fix_u.*fix_m'
  )
})
