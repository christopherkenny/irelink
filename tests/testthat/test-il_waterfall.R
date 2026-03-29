# Sprint 8 — Pair inspection: il_waterfall(), il_compare_records(),
# il_find_matches()
# Translated from: test_compare_two_records.py, test_find_new_matches.py

# --- il_compare_records() -------------------------------------------------
# From: test_compare_two_records.py

test_that('il_compare_records() scores a known pair', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact())

  record_a <- list(first_name = 'John', surname = 'Smith')
  record_b <- list(first_name = 'John', surname = 'Smyth')

  result <- il_compare_records(record_a, record_b, spec = spec, con = con)

  expect_s3_class(result, 'tbl_df')
  expect_true(nrow(result) == 1)
})

test_that('il_compare_records() shows exact match on identical records', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact())

  record <- list(first_name = 'Julia', surname = 'Taylor')

  result <- il_compare_records(record, record, spec = spec, con = con)
  # Identical records should get gamma = highest level for all comparisons
  gamma_cols <- grep('^gamma_', names(result), value = TRUE)
  # For exact match, gamma should be the top level
  expect_true(all(result[, gamma_cols] > 0))
})

# --- il_find_matches() ----------------------------------------------------
# From: test_find_new_matches.py::test_matches_work

test_that('il_find_matches() returns matches for a new record', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name, surname))

  # From: test_find_new_matches — find matches for "Eliza Smith"
  new_record <- data.frame(
    first_name = 'Eliza',
    surname = 'Smith',
    stringsAsFactors = FALSE
  )

  # With very permissive threshold, should find all surname="Smith"
  matches <- il_find_matches(model, new_record, threshold = 0.01)
  expect_s3_class(matches, 'tbl_df')
  expect_true(nrow(matches) > 0)
})

# --- il_waterfall() -------------------------------------------------------

test_that('il_waterfall() returns per-comparison weight contributions', {
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

  pairs <- predict(model, threshold = 0.5)

  if (nrow(pairs) > 0) {
    wf <- il_waterfall(pairs, which = 1L)
    expect_s3_class(wf, 'tbl_df')
    expect_equal(wf$step[1], 'Prior')
    expect_equal(wf$step[nrow(wf)], 'Final')
    expect_true(all(c('start', 'end', 'direction') %in% names(wf)))

    comp_rows <- wf[!(wf$direction %in% c('prior', 'final')), , drop = FALSE]
    expect_true(nrow(comp_rows) >= 2)
    expect_equal(
      sum(comp_rows$contribution),
      pairs$match_weight[1],
      tolerance = 0.01
    )
    expect_equal(
      wf$contribution[wf$direction == 'final'],
      wf$contribution[wf$direction == 'prior'] + pairs$match_weight[1],
      tolerance = 0.01
    )
  }
})
