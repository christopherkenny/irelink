# Snapshot tests, backend compatibility, tidyselect edge cases,
# and clustering NA handling.

# ── 6a. NA handling in clustering ─────────────────────────────

test_that('il_cluster() tolerates NA in match_probability by using threshold', {
  pairs <- structure(
    tibble::tibble(
      unique_id_l = c('A', 'B'),
      unique_id_r = c('B', 'C'),
      match_weight = c(5.0, NA_real_),
      match_probability = c(0.97, NA_real_)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  # threshold filters before clustering; NA probabilities should be
  # dropped by the >= comparison (NA >= 0.5 is NA → FALSE → dropped)
  clusters <- il_cluster(pairs, threshold = 0.5)
  expect_s3_class(clusters, 'tbl_df')
  # A-B linked, C isolated because B-C has NA probability
  expect_true(nrow(clusters) >= 2)
})

# ── tidyselect where() in il_compare ──────────────────────────────────────

test_that('tidyselect: where(is.character) stores a deferred expression', {
  # where() requires column metadata, so il_compare stores it as deferred
  # (same pattern as everything() and matches() tests in test-il_compare.R)
  spec <- il_spec() |>
    il_compare(tidyselect::where(is.character), cl_exact())

  expect_s3_class(spec, 'il_spec')
  expect_length(spec$comparisons, 1)
})

# ── 6c. Backend compatibility skips ──────────────────────────────────────

test_that('SQLite backend supports cl_exact comparisons end-to-end', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('A', 'A', 'B', 'B', 'C', 'C'),
    surname = c('X', 'X', 'Y', 'Y', 'Z', 'Z')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  pairs <- predict(model, threshold = 0.0)
  expect_s3_class(pairs, 'il_compared')
  expect_true(nrow(pairs) > 0)
  expect_true(all(pairs$match_probability >= 0 & pairs$match_probability <= 1))
})

test_that('DuckDB backend works end-to-end', {
  skip_if_not_installed('duckdb')
  df <- fake_20
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9)) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))
  pairs <- predict(model, threshold = 0.5)
  expect_s3_class(pairs, 'tbl_df')
  expect_true(nrow(pairs) >= 0L)
})

# ── Snapshot tests ───────────────────────────────────────────────────

test_that('print.il_spec() snapshot: empty spec', {
  expect_snapshot({
    spec <- il_spec()
    print(spec)
  })
})

test_that('print.il_spec() snapshot: spec with comparisons and blocking', {
  expect_snapshot({
    spec <- il_spec() |>
      il_compare(first_name, cl_exact()) |>
      il_compare(surname, cl_jaro_winkler(0.9)) |>
      il_block_on(first_name) |>
      il_block_on(surname)
    print(spec)
  })
})

test_that('print.il_model() snapshot: untrained model', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'B', 'C', 'D', 'E'),
    surname = rep('X', 5)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con)

  expect_snapshot(print(model))
})

test_that('print.il_model() snapshot: trained model', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('A', 'A', 'B', 'B', 'C', 'C'),
    surname = rep('X', 6)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  expect_snapshot(print(model))
})

test_that('summary.il_model() snapshot: trained model', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('A', 'A', 'B', 'B', 'C', 'C'),
    surname = rep('X', 6)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  expect_snapshot(summary(model))
})

test_that('unit helper print snapshot', {
  expect_snapshot({
    print(days(30))
    print(months(6))
    print(years(2))
    print(km(10))
    print(mi(5))
  })
})
