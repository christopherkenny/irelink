test_that('training functions can record SQL profile entries', {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('a', 'a', 'b', 'c'),
    surname = c('x', 'x', 'y', 'z')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact())

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 6, profile_sql = TRUE)

  expect_s3_class(model$params$sql_profile, 'tbl_df')
  expect_true(nrow(model$params$sql_profile) > 0)
  expect_true('estimate_u.random_pair_gamma_counts' %in% model$params$sql_profile$step)

  model <- il_estimate_prior(
    model,
    block_on(first_name),
    recall = 1,
    profile_sql = TRUE
  )
  expect_true('estimate_prior.count_unique_blocked_pairs' %in% model$params$sql_profile$step)
})

test_that('prediction can record SQL profile entries', {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('a', 'a', 'b', 'b', 'c', 'd'),
    surname = c('x', 'x', 'y', 'z', 'w', 'v')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 15) |>
    il_estimate_em(block_on(first_name))

  pairs <- predict(model, threshold = 0, profile_sql = TRUE)
  profile <- attr(pairs, 'sql_profile')
  expect_s3_class(profile, 'tbl_df')
  expect_true('predict.collect' %in% profile$step)

  lazy <- predict(model, threshold = 0, collect = FALSE, profile_sql = TRUE)
  expect_s3_class(lazy$sql_profile, 'tbl_df')
  expect_true('predict_lazy.create' %in% lazy$sql_profile$step)
})
