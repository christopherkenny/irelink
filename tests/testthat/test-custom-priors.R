custom_prior_data <- function() {
  n_entities <- 24L
  entity <- rep(seq_len(n_entities), each = 2L)
  block <- rep(rep(seq_len(6L), each = 4L), each = 2L)
  data.frame(
    unique_id = seq_along(entity),
    block = block,
    address = ifelse(
      entity %% 4L == 0L,
      paste0('addr_', entity, '_', rep(c('a', 'b'), n_entities)),
      paste0('addr_', entity)
    ),
    sex = ifelse(entity %% 2L == 0L, 'F', 'M'),
    stringsAsFactors = FALSE
  )
}

custom_prior_model <- function(con) {
  spec <- il_spec() |>
    il_compare(address, cl_exact()) |>
    il_compare(sex, cl_exact())

  il_model(custom_prior_data(), spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e5)
}

param_value <- function(model, comparison, level, field = 'm') {
  params <- il_parameters(model)
  params[params$comparison == comparison & params$gamma_level == level, field][[
    1
  ]]
}

test_that('prevalence priors set the start value and pull EM estimates', {
  con <- test_con()
  withr::defer(test_discon(con))

  base <- custom_prior_model(con)
  low <- base |>
    il_prior_prevalence(0.01, strength = 500) |>
    il_estimate_em(block_on(block), max_iterations = 10L)
  high <- base |>
    il_prior_prevalence(0.50, strength = 500) |>
    il_estimate_em(block_on(block), max_iterations = 10L)

  expect_equal(il_prior_prevalence(base, 0.2)$params$prior, 0.2)
  expect_lt(low$params$prior, high$params$prior)
})

test_that('matched-level priors move m probabilities in the expected direction', {
  con <- test_con()
  withr::defer(test_discon(con))

  base <- custom_prior_model(con)
  no_prior <- il_estimate_em(base, block_on(block), max_iterations = 10L)
  address_prior <- base |>
    il_prior_m(address, exact = 0.35, strength = 200) |>
    il_estimate_em(block_on(block), max_iterations = 10L)
  sex_prior <- base |>
    il_prior_m(sex, exact = 0.995, strength = 200) |>
    il_estimate_em(block_on(block), max_iterations = 10L)

  expect_lt(
    param_value(address_prior, 'address', 1L),
    param_value(no_prior, 'address', 1L)
  )
  expect_gt(
    param_value(sex_prior, 'sex', 1L),
    param_value(no_prior, 'sex', 1L)
  )
})

test_that('fixed m constraints hold requested parameters fixed', {
  con <- test_con()
  withr::defer(test_discon(con))

  model <- custom_prior_model(con) |>
    il_constrain_m(sex, exact = 0.99) |>
    il_estimate_em(block_on(block), max_iterations = 10L)

  expect_equal(param_value(model, 'sex', 1L), 0.99, tolerance = 1e-10)
  expect_equal(
    sum(il_parameters(model)$m[il_parameters(model)$comparison == 'sex']),
    1
  )
})

test_that('custom prior validation catches malformed inputs', {
  con <- test_con()
  withr::defer(test_discon(con))
  model <- custom_prior_model(con)

  expect_error(il_prior_prevalence(model, -0.1), 'probability')
  expect_error(il_prior_prevalence(model, 0), 'strictly')
  expect_error(il_prior_prevalence(model, 1), 'strictly')
  expect_error(il_prior_prevalence(model, 0.1, strength = -1), 'strength')
  expect_error(
    il_prior_m(model, missing_col, exact = 0.5, strength = 1),
    'not present'
  )
  expect_error(il_prior_m(model, address, exact = 1.2, strength = 1), 'exact')
  expect_error(
    il_prior_m(model, address, levels = c('0' = 0.2, '1' = 0.7), strength = 1),
    'sum to 1'
  )
  expect_error(
    il_prior_m(model, address, levels = c('0' = 0.2, '2' = 0.8), strength = 1),
    'gamma levels'
  )
})

test_that('updating one prior preserves unrelated prior rows', {
  con <- test_con()
  withr::defer(test_discon(con))
  model <- custom_prior_model(con) |>
    il_prior_prevalence(0.1, strength = 50) |>
    il_prior_m(address, exact = 0.4, strength = 20) |>
    il_prior_m(sex, exact = 0.9, strength = 30) |>
    il_prior_m(address, exact = 0.6, strength = 25)

  priors <- il_priors(model)
  expect_equal(nrow(priors), 5L)
  expect_equal(
    unique(priors$strength[which(priors$comparison == 'address')]),
    25
  )
  expect_equal(unique(priors$strength[which(priors$comparison == 'sex')]), 30)
  expect_equal(nrow(priors[priors$family == 'prevalence', ]), 1L)
})

test_that('priors and constraints on deactivated comparisons error clearly', {
  con <- test_con()
  withr::defer(test_discon(con))

  model <- custom_prior_model(con) |>
    il_prior_m(address, exact = 0.5, strength = 10)
  expect_error(
    il_estimate_em(model, block_on(address)),
    'deactivated'
  )

  constrained <- custom_prior_model(con) |>
    il_constrain_m(sex, exact = 0.99)
  expect_error(
    il_estimate_em(constrained, block_on(sex)),
    'deactivated'
  )
})

test_that('custom prior metadata round-trips through RDS save/load', {
  con <- test_con()
  withr::defer(test_discon(con))

  model <- custom_prior_model(con) |>
    il_prior_prevalence(0.1, strength = 50) |>
    il_prior_m(address, exact = 0.4, strength = 20) |>
    il_constrain_m(sex, exact = 0.99) |>
    il_estimate_em(block_on(block), max_iterations = 5L)

  tmp <- withr::local_tempfile(fileext = '.rds')
  il_save(model, tmp)
  loaded <- il_load(tmp)

  expect_equal(il_priors(loaded), il_priors(model))
  expect_equal(il_constraints(loaded), il_constraints(model))
})

test_that('custom prior metadata is intentionally RDS-only, not Splink JSON', {
  skip_if_no_jsonlite()

  con <- test_con()
  withr::defer(test_discon(con))

  model <- custom_prior_model(con) |>
    il_prior_prevalence(0.1, strength = 50) |>
    il_prior_m(address, exact = 0.4, strength = 20) |>
    il_constrain_m(sex, exact = 0.99)

  tmp <- withr::local_tempfile(fileext = '.json')
  il_save(model, tmp)
  raw <- jsonlite::read_json(tmp, simplifyVector = FALSE)
  loaded <- suppressWarnings(il_load(tmp))

  expect_null(raw$priors)
  expect_null(raw$constraints)
  expect_equal(nrow(il_priors(loaded)), 0L)
  expect_equal(nrow(il_constraints(loaded)), 0L)
})
