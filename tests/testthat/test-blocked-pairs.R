# Tests for materialized blocked-pairs helpers

blocked_pair_count <- function(model) {
  tbl <- model$data$blocked_pairs[['predict']]
  nrow(DBI::dbReadTable(model$con, tbl))
}

test_that('register_blocked_pairs() deduplicates overlapping blocking rules', {
  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:3,
    first_name = c('a', 'a', 'b'),
    surname = c('x', 'x', 'y')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact())

  model <- il_model(df, spec = spec, con = con)
  model <- register_blocked_pairs(
    model,
    list(block_on(first_name), block_on(surname))
  )

  pairs <- DBI::dbReadTable(con, model$data$blocked_pairs[['predict']])
  expect_equal(nrow(pairs), 1)
  expect_equal(pairs$l_unique_id, 1)
  expect_equal(pairs$r_unique_id, 2)
})

test_that('register_blocked_pairs() handles dedupe, link, and link_and_dedupe', {
  con <- test_con()
  withr::defer(test_discon(con))

  spec <- il_spec() |>
    il_compare(key, cl_exact())

  df <- data.frame(unique_id = 1:3, key = 'a')
  dedupe <- il_model(df, spec = spec, con = con) |>
    register_blocked_pairs(list(block_on(key)))
  expect_equal(blocked_pair_count(dedupe), 3)

  df_l <- data.frame(unique_id = 1:2, key = 'a')
  df_r <- data.frame(unique_id = 10:12, key = 'a')
  link <- il_model(df_l, df_r,
    spec = spec, con = con, link_type = 'link'
  ) |>
    register_blocked_pairs(list(block_on(key)))
  expect_equal(blocked_pair_count(link), 6)

  both_l <- data.frame(unique_id = 1:2, key = 'a')
  both_r <- data.frame(unique_id = 10:11, key = 'a')
  link_dedupe <- il_model(both_l, both_r,
    spec = spec, con = con, link_type = 'link_and_dedupe'
  ) |>
    register_blocked_pairs(list(block_on(key)))
  expect_equal(blocked_pair_count(link_dedupe), 6)
})

test_that('register_blocked_pairs() preserves character ids and raw where rules', {
  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = c('id-a', 'id-b', 'id-c'),
    name = c('x', 'x', 'y')
  )
  spec <- il_spec() |>
    il_compare(name, cl_exact())

  model <- il_model(df, spec = spec, con = con) |>
    register_blocked_pairs(list(block_on(.where = 'l.name = r.name')))

  pairs <- DBI::dbReadTable(con, model$data$blocked_pairs[['predict']])
  expect_equal(nrow(pairs), 1)
  expect_equal(pairs$l_unique_id, 'id-a')
  expect_equal(pairs$r_unique_id, 'id-b')
})

test_that('register_blocked_pairs() and prior counting respect exploded blocking', {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  DBI::dbExecute(con, '
    CREATE TABLE arr_test (
      unique_id INTEGER,
      name VARCHAR,
      emails VARCHAR[]
    )
  ')
  DBI::dbExecute(con, "
    INSERT INTO arr_test VALUES
      (1, 'Alice', ['alice@a.com', 'alice@b.com']),
      (2, 'Bob',   ['bob@a.com']),
      (3, 'Carol', ['alice@b.com', 'carol@c.com'])
  ")

  spec <- il_spec() |>
    il_compare(name, cl_exact())
  model <- il_model(dplyr::tbl(con, 'arr_test'), spec = spec, con = con)

  model_blocked <- register_blocked_pairs(
    model,
    list(block_on(emails, .explode = 'emails'))
  )
  pairs <- DBI::dbReadTable(con, model_blocked$data$blocked_pairs[['predict']])

  expect_equal(nrow(pairs), 1L)
  expect_equal(pairs$l_unique_id, 1L)
  expect_equal(pairs$r_unique_id, 3L)

  model_prior <- il_estimate_prior(
    model,
    block_on(emails, .explode = 'emails'),
    recall = 1
  )
  expect_equal(model_prior$params$prior, 1 / 3)
})

test_that('predict() agrees with and without registered blocked pairs', {
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

  expected <- predict(model, threshold = 0)
  registered <- register_blocked_pairs(model)
  actual <- predict(registered, threshold = 0)

  order_cols <- c('unique_id_l', 'unique_id_r')
  expected <- dplyr::arrange(expected, !!!rlang::syms(order_cols))
  actual <- dplyr::arrange(actual, !!!rlang::syms(order_cols))
  expect_equal(actual, expected, ignore_attr = TRUE)
})
