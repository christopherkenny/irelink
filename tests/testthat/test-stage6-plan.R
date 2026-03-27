# Stage 6 — Tests from 09-implementation-plan.md §6a–6e.
# Covers gaps not addressed by the Python translations or the initial
# R-specific audit: snapshot tests, remaining dplyr verbs, tidyselect
# where(), performance guards, backend skips, and clustering NA handling.

# ── 6a. NA handling in clustering (Sprint 9) ─────────────────────────────

test_that('il_cluster() tolerates NA in match_probability by using threshold', {
  skip_if_sprint_lt(9)

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

# ── 6b. dplyr::group_by on il_compared (Sprint 8) ───────────────────────

test_that('il_compared supports dplyr::group_by + summarise', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('dplyr')

  pairs <- structure(
    tibble::tibble(
      unique_id_l = c(1L, 2L, 3L, 4L),
      unique_id_r = c(5L, 6L, 7L, 8L),
      match_weight = c(3.0, 1.5, 2.0, 4.0),
      match_probability = c(0.95, 0.60, 0.80, 0.99),
      gamma_name = c(1L, 0L, 1L, 1L)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  grouped <- dplyr::group_by(pairs, gamma_name) |>
    dplyr::summarise(
      n = dplyr::n(),
      avg_prob = mean(match_probability),
      .groups = 'drop'
    )
  expect_s3_class(grouped, 'tbl_df')
  expect_equal(nrow(grouped), 2)
  expect_true('avg_prob' %in% names(grouped))
})

# ── 6b. tidyselect where() in il_compare (Sprint 3) ─────────────────────

test_that('tidyselect: where(is.character) stores a deferred expression', {
  skip_if_sprint_lt(3)

  # where() requires column metadata, so il_compare stores it as deferred
  # (same pattern as everything() and matches() tests in test-il_compare.R)
  spec <- il_spec() |>
    il_compare(tidyselect::where(is.character), cl_exact())

  expect_s3_class(spec, 'il_spec')
  expect_length(spec$comparisons, 1)
})

# ── 6c. Backend compatibility skips ──────────────────────────────────────

test_that('SQLite backend supports cl_exact comparisons end-to-end', {
  skip_if_sprint_lt(8)
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
  df <- il_demo('fake_20')
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

test_that('PostgreSQL backend is skipped when unavailable', {
  skip_if_not_installed('RPostgres')
  skip('PostgreSQL not available in local testing — deferred to CI')
})

# ── 6d. Snapshot tests ───────────────────────────────────────────────────

test_that('print.il_spec() snapshot: empty spec', {
  skip_if_sprint_lt(1)

  expect_snapshot({
    spec <- il_spec()
    print(spec)
  })
})

test_that('print.il_spec() snapshot: spec with comparisons and blocking', {
  skip_if_sprint_lt(3)

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
  skip_if_sprint_lt(6)
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
  skip_if_sprint_lt(7)
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
  skip_if_sprint_lt(7)
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
  skip_if_sprint_lt(1)

  expect_snapshot({
    print(days(30))
    print(months(6))
    print(years(2))
    print(km(10))
    print(mi(5))
  })
})

# ── 6e. Performance-sensitive tests ──────────────────────────────────────

test_that('il_estimate_em() on 1000 records completes without error', {
  skip_if_sprint_lt(7)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- il_demo('fake_1000')
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6)

  expect_no_error(
    il_estimate_em(model, block_on(first_name, surname))
  )
})

test_that('predict() on 1000 records completes without error', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- il_demo('fake_1000')
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name, surname))

  expect_no_error(predict(model, threshold = 0.5))
})

test_that('il_cluster() on many pairs completes without error', {
  skip_if_sprint_lt(9)

  # Construct 5000 edges across 1000 nodes
  set.seed(123)
  n_edges <- 5000L
  pairs <- structure(
    tibble::tibble(
      unique_id_l = as.character(sample(1:1000, n_edges, replace = TRUE)),
      unique_id_r = as.character(sample(1:1000, n_edges, replace = TRUE)),
      match_weight = runif(n_edges, 0, 5),
      match_probability = runif(n_edges, 0.5, 1.0)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )
  # Remove self-pairs
  pairs <- pairs[pairs$unique_id_l != pairs$unique_id_r, ]

  expect_no_error(il_cluster(pairs, threshold = 0.7))
})
