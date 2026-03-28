# Sprint 7 — Model inspection: il_weights(), il_parameters(),
# il_training_history()

# --- il_weights() ---------------------------------------------------------

test_that('il_weights() returns a tibble with expected columns', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 df <- fake_1000
 spec <- il_spec() |>
 il_compare(first_name, cl_exact()) |>
 il_compare(surname, cl_exact()) |>
 il_block_on(first_name) |>
 il_block_on(surname)

 model <- il_model(df, spec = spec, con = con) |>
 il_estimate_u(max_pairs = 1e6) |>
 il_estimate_em(block_on(first_name, surname))

 w <- il_weights(model)
 expect_s3_class(w, 'tbl_df')
 expect_true('comparison' %in% names(w))
 expect_true('level' %in% names(w))
 expect_true('weight' %in% names(w))
})

test_that('il_weights() has one row per comparison level', {
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

 w <- il_weights(model)
 # At minimum: 2 comparisons × 2 levels (match/non-match) = 4 rows
 expect_true(nrow(w) >= 4)
})

# --- il_parameters() ------------------------------------------------------

test_that('il_parameters() returns a tibble with m and u in [0, 1]', {
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

 p <- il_parameters(model)
 expect_s3_class(p, 'tbl_df')
 expect_true('m' %in% names(p))
 expect_true('u' %in% names(p))
 expect_true(all(p$m >= 0 & p$m <= 1))
 expect_true(all(p$u >= 0 & p$u <= 1))
})

# --- il_training_history() ------------------------------------------------

test_that('il_training_history() returns convergence data', {
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

 h <- il_training_history(model)
 expect_s3_class(h, 'tbl_df')
 expect_true('iteration' %in% names(h))
 # Values should converge (later iterations change less)
 expect_true(nrow(h) > 0)
})
