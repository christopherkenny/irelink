# Sprint 10 — Serialisation: il_save(), il_load()
# From: test_full_example_duckdb.py (save/load model)

test_that('il_save() and il_load() round-trip preserves model parameters', {
  skip_if_no_jsonlite()
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

  tmp <- withr::local_tempfile(fileext = '.json')
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

test_that('il_save() creates a valid settings JSON file', {
  skip_if_no_jsonlite()
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

  tmp <- withr::local_tempfile(fileext = '.json')
  il_save(model, tmp)

  raw <- jsonlite::read_json(tmp, simplifyVector = FALSE)
  expect_type(raw, 'list')
  expect_named(raw, c(
    'link_type',
    'probability_two_random_records_match',
    'em_convergence',
    'max_iterations',
    'retain_matching_columns',
    'retain_intermediate_calculation_columns',
    'additional_columns_to_retain',
    'unique_id_column_name',
    'source_dataset_column_name',
    'comparison_vector_value_column_prefix',
    'sql_dialect',
    'blocking_rules_to_generate_predictions',
    'comparisons'
  ))
  expect_equal(raw$link_type, 'dedupe_only')
  expect_true(length(raw$comparisons) > 0L)
  expect_true(length(raw$blocking_rules_to_generate_predictions) > 0L)
  expect_false(any(grepl('__irelink__', readLines(tmp, warn = FALSE), fixed = TRUE)))
})

test_that('il_save() still creates a valid RDS file', {
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

test_that('il_load() accepts a valid Splink JSON model and predict() works after attach', {
  skip_if_no_jsonlite()

  model_json <- list(
    link_type = 'dedupe_only',
    probability_two_random_records_match = 0.05,
    comparisons = list(
      list(
        output_column_name = 'first_name',
        comparison_levels = list(
          list(
            sql_condition = 'first_name_l = first_name_r',
            m_probability = 0.9,
            u_probability = 0.2,
            fix_m_probability = FALSE,
            fix_u_probability = FALSE
          ),
          list(
            sql_condition = 'ELSE',
            m_probability = 0.1,
            u_probability = 0.8,
            fix_m_probability = FALSE,
            fix_u_probability = FALSE
          )
        )
      ),
      list(
        output_column_name = 'surname',
        comparison_levels = list(
          list(
            sql_condition = 'surname_l = surname_r',
            m_probability = 0.95,
            u_probability = 0.1,
            fix_m_probability = FALSE,
            fix_u_probability = FALSE
          ),
          list(
            sql_condition = 'ELSE',
            m_probability = 0.05,
            u_probability = 0.9,
            fix_m_probability = FALSE,
            fix_u_probability = FALSE
          )
        )
      )
    ),
    blocking_rules_to_generate_predictions = list(
      list(
        blocking_rule = 'surname_l = surname_r',
        sql_dialect = 'duckdb'
      )
    )
  )

  path <- withr::local_tempfile(fileext = '.json')
  jsonlite::write_json(
    model_json,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = 'null',
    digits = NA
  )

  loaded <- il_load(path)
  expect_s3_class(loaded, 'il_model')
  expect_true(loaded$trained)

  con <- test_con()
  withr::defer(test_discon(con))

  new_df <- data.frame(
    unique_id = 1:6,
    first_name = c('John', 'John', 'Jane', 'Jane', 'Bob', 'Bobby'),
    surname = c('Smith', 'Smith', 'Doe', 'Doe', 'Jones', 'Jones'),
    stringsAsFactors = FALSE
  )

  attached <- il_attach(loaded, new_df, con = con)
  pairs <- predict(attached, threshold = 0)

  expect_s3_class(pairs, 'il_compared')
  expect_gt(nrow(pairs), 0)
  expect_true(all(c('match_weight', 'match_probability') %in% names(pairs)))
})
