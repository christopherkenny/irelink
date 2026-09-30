tf_test_model <- function(con) {
  spec <- il_spec() |>
    il_compare(first_name, cl_exact(term_frequency = TRUE)) |>
    il_compare(surname, cl_levenshtein(2)) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname)
  suppressMessages(
    il_model(fake_1000, spec = spec, con = con) |>
      il_estimate_u() |>
      il_estimate_em(block_on(dob))
  )
}

test_that('il_score_pairs() reproduces predict() scores', {
  con <- test_con()
  withr::defer(test_discon(con))
  model <- tf_test_model(con)

  pair <- predict(model, threshold = 0)[1, ]
  scored <- il_score_pairs(
    model,
    fake_1000[fake_1000$unique_id == pair$unique_id_l, ],
    fake_1000[fake_1000$unique_id == pair$unique_id_r, ]
  )

  expect_s3_class(scored, 'il_compared')
  expect_equal(scored$match_weight, pair$match_weight)
  expect_equal(scored$match_probability, pair$match_probability)
})

test_that('il_score_pairs() reproduces predict() scores on SQLite', {
  skip_if_not_installed('RSQLite')
  con <- DBI::dbConnect(RSQLite::SQLite(), ':memory:')
  withr::defer(DBI::dbDisconnect(con))
  model <- tf_test_model(con)

  pair <- predict(model, threshold = 0)[1, ]
  scored <- il_score_pairs(
    model,
    fake_1000[fake_1000$unique_id == pair$unique_id_l, ],
    fake_1000[fake_1000$unique_id == pair$unique_id_r, ]
  )

  expect_equal(scored$match_weight, pair$match_weight)
})

test_that('il_score_pairs() scores every pair and leaves no tables', {
  con <- test_con()
  withr::defer(test_discon(con))
  model <- tf_test_model(con)
  tables_before <- DBI::dbListTables(con)

  scored <- il_score_pairs(model, fake_1000[1:3, ], fake_1000[4:5, ])

  expect_equal(nrow(scored), 6)
  expect_setequal(DBI::dbListTables(con), tables_before)
})

test_that('il_score_pairs() works on a loaded model without a connection', {
  skip_if_no_jsonlite()
  con <- test_con()
  withr::defer(test_discon(con))
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(surname)
  model <- suppressMessages(
    il_model(fake_1000, spec = spec, con = con) |>
      il_estimate_u() |>
      il_estimate_em(block_on(dob))
  )
  path <- withr::local_tempfile(fileext = '.json')
  il_save(model, path)

  scored <- il_score_pairs(il_load(path), fake_1000[1, ], fake_1000[2:3, ])

  expect_equal(nrow(scored), 2)
  expect_all_true(is.finite(scored$match_weight))
})

test_that('il_score_pairs() errors without term-frequency tables', {
  con <- test_con()
  withr::defer(test_discon(con))
  model <- tf_test_model(con)
  other <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(other, shutdown = TRUE))

  expect_snapshot(
    il_score_pairs(model, fake_1000[1, ], fake_1000[2, ], con = other),
    error = TRUE
  )
})

test_that('il_score_pairs() errors on missing columns', {
  con <- test_con()
  withr::defer(test_discon(con))
  model <- tf_test_model(con)

  expect_snapshot(
    il_score_pairs(model, fake_1000[1, ], data.frame(first_name = 'a')),
    error = TRUE
  )
})
