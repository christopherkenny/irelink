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
  expect_true(
    'estimate_u.random_pair_gamma_counts' %in% model$params$sql_profile$step
  )

  model <- il_estimate_prior(
    model,
    block_on(first_name),
    recall = 1,
    profile_sql = TRUE
  )
  expect_true(
    'estimate_prior.count_unique_blocked_pairs' %in%
      model$params$sql_profile$step
  )
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

  collected <- collect_il_compared_lazy(lazy)
  collected_profile <- attr(collected, 'sql_profile')
  expect_s3_class(collected_profile, 'tbl_df')
  expect_identical(collected_profile, lazy$sql_profile)
})

test_that('SQL wrappers record rows and statements when profiling is enabled', {
  con <- test_con()
  withr::defer(test_discon(con))
  profile <- il_new_sql_profile(TRUE)

  il_db_execute(con, 'CREATE TABLE timing_test (x INTEGER)', 'create', profile)
  il_db_get_query(con, 'SELECT 1 AS x', 'query', profile)

  entries <- il_sql_profile_entries(profile)
  expect_equal(entries$step, c('create', 'query'))
  expect_equal(entries$rows, c(0L, 1L))
  expect_all_true(nzchar(entries$statement))
  expect_all_true(is.finite(entries$elapsed))
})

test_that('SQL wrappers print statements when irelink.show_sql is TRUE', {
  con <- test_con()
  withr::defer(test_discon(con))
  withr::local_options(irelink.show_sql = TRUE)

  expect_snapshot(il_db_get_query(con, 'SELECT 1 AS x', 'query'))
})

test_that('SQL wrappers stay quiet by default', {
  con <- test_con()
  withr::defer(test_discon(con))

  expect_no_message(il_db_get_query(con, 'SELECT 1 AS x', 'query'))
})

test_that('format_sql() lays out clauses, conditions, and CASE branches', {
  sql <- paste(
    'SELECT COUNT(*) AS n, CASE WHEN l.x = r.x THEN 1 ELSE 0 END AS g',
    'FROM (SELECT l.unique_id FROM "t" l, "t" r',
    'WHERE l.unique_id < r.unique_id AND l.x = r.x) AS pairs',
    'LEFT JOIN "tf" ON pairs.x = tf.x GROUP BY g'
  )

  expect_snapshot(cat(format_sql(sql)))
})

test_that('format_sql() only changes whitespace and leaves literals alone', {
  sql <- "SELECT 'a FROM b WHERE c' AS s, \"select\" FROM t WHERE x = 'AND'"
  formatted <- format_sql(sql)

  expect_equal(gsub('\\s+', '', formatted), gsub('\\s+', '', sql))
  expect_match(formatted, "'a FROM b WHERE c'", fixed = TRUE)
  expect_match(formatted, "x = 'AND'", fixed = TRUE)
})

test_that('irelink.show_sql prints SQL from functions without a step label', {
  con <- test_con()
  withr::defer(test_discon(con))
  withr::local_options(irelink.show_sql = TRUE)

  expect_message(il_completeness(fake_1000, con = con), 'SELECT')
})
