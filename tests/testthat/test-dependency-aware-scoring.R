make_dependency_model <- function(df, con) {
  spec <- il_spec() |>
    il_compare(a, cl_exact()) |>
    il_compare(b, cl_exact()) |>
    il_block_on(.where = '1=1')

  il_model(df, spec = spec, con = con)
}

test_that('dependency-aware scoring learns field dependence', {
  skip_if_not_installed('RSQLite')

  df <- data.frame(
    unique_id = 1:10,
    a = c('x', 'x', 'x', 'x', 'y', 'y', 'z', 'z', 'w', 'v'),
    b = c('p', 'p', 'q', 'q', 'p', 'q', 'r', 's', 't', 'u')
  )
  con_i <- test_con()
  withr::defer(test_discon(con_i))
  con_d <- test_con()
  withr::defer(test_discon(con_d))

  independent <- make_dependency_model(df, con_i) |>
    il_estimate_em(block_on(.where = '1=1'), max_iterations = 15L)
  dependent <- make_dependency_model(df, con_d) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 15L,
      estimator_mode = 'dependency-aware'
    )

  patterns <- data.frame(gamma_a = c(0L, 1L, 0L, 1L), gamma_b = c(0L, 0L, 1L, 1L))
  score_i <- il_score_patterns(independent, patterns)
  score_d <- il_score_patterns(dependent, patterns)

  expect_true(any(abs(score_i$match_probability - score_d$match_probability) > 1e-6))
  expect_true(all(score_d$match_probability > 0 & score_d$match_probability < 1))
})

test_that('dependency-aware scoring treats missing states as explicit levels', {
  skip_if_not_installed('RSQLite')

  df <- data.frame(
    unique_id = 1:6,
    a = c('x', 'x', NA, NA, 'y', 'z'),
    b = c('p', 'q', 'p', NA, 'q', 'r')
  )
  spec <- il_spec() |>
    il_compare(a, cl_levels(cl_null(), cl_exact(), cl_else())) |>
    il_compare(b, cl_exact()) |>
    il_block_on(.where = '1=1')
  con <- test_con()
  withr::defer(test_discon(con))

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 25L,
      convergence = 1,
      estimator_mode = 'dependency-aware'
    )
  scored <- il_score_patterns(model, data.frame(gamma_a = -1L, gamma_b = 0L))

  expect_equal(as.character(model$params$dependency_aware$levels$a[1]), '-1')
  expect_true(is.finite(scored$match_probability))
  expect_true(scored$match_probability > 0 && scored$match_probability < 1)
})

test_that('dependency-aware model scores compatible larger pattern tables', {
  skip_if_not_installed('RSQLite')

  df <- data.frame(
    unique_id = 1:5,
    a = c('x', 'x', 'y', 'z', 'q'),
    b = c('p', 'p', 'r', 's', 't')
  )
  con <- test_con()
  withr::defer(test_discon(con))
  model <- make_dependency_model(df, con) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 10L,
      estimator_mode = 'dependency-aware'
    )

  scored <- il_score_patterns(model, data.frame(
    gamma_a = c(0L, 0L, 1L, 1L),
    gamma_b = c(0L, 1L, 0L, 1L),
    n = c(100L, 5L, 7L, 2L)
  ))
  scored_single <- il_score_patterns(model, data.frame(gamma_a = 0L, gamma_b = 1L))

  expect_equal(nrow(scored), 4L)
  expect_true(all(is.finite(scored$match_weight)))
  expect_true(all(scored$match_probability > 0 & scored$match_probability < 1))
  expect_equal(scored$match_probability[2], scored_single$match_probability)
})

test_that('dependency-aware training handles unobserved compatible gamma levels', {
  skip_if_not_installed('RSQLite')

  df <- data.frame(
    unique_id = 1:6,
    a = c('aaaa', 'aaaa', 'bbbb', 'cccc', 'dddd', 'eeee'),
    b = c('p', 'q', 'r', 's', 't', 'u')
  )
  spec <- il_spec() |>
    il_compare(a, cl_jaro_winkler(0.98, 0.90)) |>
    il_compare(b, cl_exact()) |>
    il_block_on(.where = '1=1')
  con <- test_con()
  withr::defer(test_discon(con))

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 10L,
      estimator_mode = 'dependency-aware'
    )
  scored <- il_score_patterns(model, data.frame(gamma_a = 1L, gamma_b = 0L))

  expect_true('1' %in% model$params$dependency_aware$levels$a)
  expect_true(is.finite(scored$match_probability))
  expect_true(scored$match_probability > 0 && scored$match_probability < 1)
})

test_that('dependency-aware scoring rejects unsupported combinations', {
  skip_if_not_installed('RSQLite')

  df <- data.frame(
    unique_id = 1:4,
    a = c('x', 'x', 'y', 'z'),
    b = c('p', 'q', 'p', 'r')
  )
  con0 <- test_con()
  withr::defer(test_discon(con0))
  model <- make_dependency_model(df, con0)

  expect_error(
    model |>
      il_prior_prevalence(0.2, strength = 10) |>
      il_estimate_em(block_on(.where = '1=1'), estimator_mode = 'dependency-aware'),
    'Regularizing priors'
  )
  expect_error(
    model |>
      il_constrain_m(a, exact = 0.9) |>
      il_estimate_em(block_on(.where = '1=1'), estimator_mode = 'dependency-aware'),
    'Fixed field constraints'
  )

  spec_tf <- il_spec() |>
    il_compare(a, cl_exact(term_frequency = TRUE)) |>
    il_compare(b, cl_exact()) |>
    il_block_on(.where = '1=1')
  con <- test_con()
  withr::defer(test_discon(con))
  model_tf <- il_model(df, spec = spec_tf, con = con)
  expect_error(
    il_estimate_em(model_tf, block_on(.where = '1=1'), estimator_mode = 'dependency-aware'),
    'Term-frequency'
  )

  expect_error(
    il_estimate_em(model, block_on(a), estimator_mode = 'dependency-aware'),
    'overlap'
  )
  expect_error(
    il_estimate_em(
      model,
      block_on(.where = '1=1'),
      estimator_mode = 'dependency-aware',
      fix_m = TRUE
    ),
    'fix_m'
  )
  expect_error(
    il_estimate_em(
      model,
      block_on(.where = '1=1'),
      estimator_mode = 'dependency-aware',
      estimate_without_tf = FALSE
    ),
    'estimate_without_tf'
  )
  expect_error(
    il_estimate_em(
      model,
      block_on(.where = '1=1'),
      estimator_mode = 'dependency-aware',
      derive_prior = TRUE
    ),
    'derive_prior'
  )
})

test_that('dependency-aware estimator survives save, load, and attach', {
  skip_if_not_installed('RSQLite')

  df <- data.frame(
    unique_id = 1:6,
    a = c('x', 'x', 'x', 'y', 'z', 'z'),
    b = c('p', 'p', 'q', 'q', 'r', 's')
  )
  con <- test_con()
  withr::defer(test_discon(con))
  spec <- il_spec() |>
    il_compare(a, cl_exact()) |>
    il_compare(b, cl_exact()) |>
    il_block_on(.where = '1=1')
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 10L,
      estimator_mode = 'dependency-aware'
    )

  path <- tempfile(fileext = '.rds')
  il_save(model, path, overwrite = TRUE)
  loaded <- il_load(path)

  con2 <- test_con()
  withr::defer(test_discon(con2))
  attached <- il_attach(loaded, df, con = con2)
  pairs <- predict(attached, threshold = 0)

  expect_identical(loaded$params$estimator_mode, 'dependency-aware')
  expect_s3_class(pairs, 'il_compared')
  expect_true(all(pairs$match_probability > 0 & pairs$match_probability < 1))
})

test_that('dependency-aware predict supports DuckDB lazy scoring via pattern lookup', {
  skip_if_not_installed('duckdb')

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(
    unique_id = 1:6,
    a = c('x', 'x', 'x', 'y', 'z', 'z'),
    b = c('p', 'p', 'q', 'q', 'r', 's')
  )
  model <- make_dependency_model(df, con) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 10L,
      estimator_mode = 'dependency-aware'
    )

  collected <- predict(model, threshold = 0)
  lazy <- predict(model, threshold = 0, collect = FALSE)
  lazy_pairs <- collect_il_compared_lazy(lazy)

  collected <- collected[order(collected$unique_id_l, collected$unique_id_r), ]
  lazy_pairs <- lazy_pairs[order(lazy_pairs$unique_id_l, lazy_pairs$unique_id_r), ]

  expect_s3_class(lazy, 'il_compared_lazy')
  expect_equal(lazy_pairs$unique_id_l, collected$unique_id_l)
  expect_equal(lazy_pairs$unique_id_r, collected$unique_id_r)
  expect_equal(lazy_pairs$match_weight, collected$match_weight)
  expect_equal(lazy_pairs$match_probability, collected$match_probability)
})

test_that('dependency-aware il_find_matches scores through the SQL pattern lookup path', {
  skip_if_not_installed('duckdb')

  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  df <- data.frame(
    unique_id = 1:6,
    a = c('x', 'x', 'x', 'y', 'z', 'z'),
    b = c('p', 'p', 'q', 'q', 'r', 's')
  )
  model <- make_dependency_model(df, con) |>
    il_estimate_em(
      block_on(.where = '1=1'),
      max_iterations = 10L,
      estimator_mode = 'dependency-aware'
    )

  matches <- il_find_matches(
    model,
    data.frame(a = c('x', 'z'), b = c('p', 'r')),
    threshold = 0
  )

  expect_true(nrow(matches) > 0L)
  expect_true(all(is.finite(matches$match_weight)))
  expect_true(all(matches$match_probability > 0 & matches$match_probability < 1))
})
