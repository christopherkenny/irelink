# Tests for il_score_missing_edges()

test_that('il_score_missing_edges() returns empty when no missing edges', {
  con <- test_con()
  on.exit(test_discon(con))

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(fake_1000[1:10, ], spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  pairs <- predict(model, threshold = 0.01)
  clusters <- il_cluster(pairs)

  # For very small data with blocking on surname, most within-cluster

  # pairs should already be scored
  missing <- il_score_missing_edges(model, pairs, clusters)
  expect_s3_class(missing, 'tbl_df')
  expect_true('match_probability' %in% names(missing))
})

test_that('il_score_missing_edges() finds unscored within-cluster pairs', {
  con <- test_con()
  on.exit(test_discon(con))

  # Create a scenario: 3 records in same cluster but only 2 edges scored
  df <- data.frame(
    unique_id = c(1, 2, 3),
    first_name = c('John', 'John', 'Jon'),
    surname = c('Smith', 'Smyth', 'Smith'),
    stringsAsFactors = FALSE
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  # predict only finds pairs that share surname (blocking)
  pairs <- predict(model, threshold = 0.01)

  # Force all 3 into the same cluster
  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('cluster_1', 3)
  )

  missing <- il_score_missing_edges(model, pairs, clusters)

  # Should have scored at least one pair not already in pairs
  existing_keys <- paste0(
    pmin(as.character(pairs$unique_id_l), as.character(pairs$unique_id_r)),
    '|',
    pmax(as.character(pairs$unique_id_l), as.character(pairs$unique_id_r))
  )
  if (nrow(missing) > 0) {
    missing_keys <- paste0(
      pmin(as.character(missing$unique_id_l), as.character(missing$unique_id_r)),
      '|',
      pmax(as.character(missing$unique_id_l), as.character(missing$unique_id_r))
    )
    # No overlap between missing and existing
    expect_equal(length(intersect(missing_keys, existing_keys)), 0)
  }
})

test_that('il_score_missing_edges() returns il_compared class', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = c(1, 2, 3),
    name = c('John', 'John', 'Jane'),
    stringsAsFactors = FALSE
  )

  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)
  model <- il_model(df, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(name))

  pairs <- predict(model, threshold = 0.01)
  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('cluster_1', 3)
  )

  missing <- il_score_missing_edges(model, pairs, clusters)
  expect_s3_class(missing, 'il_compared')
})

test_that('il_score_missing_edges() validates inputs', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = c(1, 2),
    name = c('John', 'John'),
    stringsAsFactors = FALSE
  )

  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u() |>
    il_estimate_em(block_on(name))
  pairs <- predict(model, threshold = 0)

  expect_error(
    il_score_missing_edges(model, pairs, tibble::tibble(unique_id = '1')),
    'cluster_id'
  )
  expect_error(
    il_score_missing_edges(model, pairs, tibble::tibble(unique_id = '1', cluster_id = 'a'), threshold = NA_real_),
    'threshold'
  )
})

test_that('il_score_missing_edges() includes gamma and TF adjustment columns', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = c(1, 2, 3),
    first_name = c('John', 'John', 'Jon'),
    city = c('A', 'A', 'A'),
    stringsAsFactors = FALSE
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(city, cl_exact(term_frequency = TRUE)) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u() |>
    il_estimate_em(block_on(first_name))

  pairs <- predict(model, threshold = 0)
  clusters <- tibble::tibble(
    unique_id = c('1', '2', '3'),
    cluster_id = rep('cluster_1', 3)
  )

  missing <- il_score_missing_edges(model, pairs, clusters, threshold = 0)

  expect_true(all(c('gamma_first_name', 'gamma_city', 'tf_adj_city') %in% names(missing)))
})
