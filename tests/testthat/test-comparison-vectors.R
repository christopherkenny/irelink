test_that('il_comparison_vectors returns distribution', {
  skip_if_not_installed('duckdb')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(city))

  vectors <- il_comparison_vectors(model)
  expect_s3_class(vectors, 'il_comparison_vectors')
  expect_true('gamma_first_name' %in% names(vectors))
  expect_true('gamma_surname' %in% names(vectors))
  expect_true('count' %in% names(vectors))
  expect_true('proportion' %in% names(vectors))
  expect_equal(sum(vectors$proportion), 1, tolerance = 1e-10)
})

test_that('il_comparison_vectors autoplot returns ggplot', {
  skip_if_not_installed('duckdb')
  skip_if_not_installed('ggplot2')
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(city)
  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(city))

  vectors <- il_comparison_vectors(model)
  p <- ggplot2::autoplot(vectors)
  expect_s3_class(p, 'ggplot')
})
