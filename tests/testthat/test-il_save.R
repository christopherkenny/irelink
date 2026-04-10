# Sprint 10 — Serialisation: il_save(), il_load()
# From: test_full_example_duckdb.py (save/load model)

test_that('il_save() and il_load() round-trip preserves model parameters', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  tmp <- withr::local_tempfile(fileext = '.rds')
  il_save(model, tmp)

  expect_true(file.exists(tmp))

  model2 <- il_load(tmp)
  expect_s3_class(model2, 'il_model')

  # Parameters should match
  p1 <- il_parameters(model)
  p2 <- il_parameters(model2)

  expect_equal(p1$m, p2$m, tolerance = 1e-6)
  expect_equal(p1$u, p2$u, tolerance = 1e-6)
})

test_that('il_save() creates a valid RDS file', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'B', 'C'),
    surname = rep('X', 5)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  tmp <- withr::local_tempfile(fileext = '.rds')
  il_save(model, tmp)

  raw <- readRDS(tmp)
  expect_type(raw, 'list')
  expect_named(raw, c('spec', 'params', 'trained', 'link_type', 'data_info'))
})

test_that('il_load() errors on non-existent file', {
  expect_error(il_load('nonexistent_file.rds'))
})

test_that('il_save() with untrained model still works', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:3,
    first_name = c('A', 'B', 'C'),
    surname = rep('X', 3)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)

  tmp <- withr::local_tempfile(fileext = '.rds')
  il_save(model, tmp)
  model2 <- il_load(tmp)
  expect_s3_class(model2, 'il_model')
})
