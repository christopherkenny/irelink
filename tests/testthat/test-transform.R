test_that('JSON save writes Splink SQL for transformed comparisons and loaded model predicts', {
  skip_if_no_jsonlite()
  spec <- il_spec() |>
    il_compare(name, cl_exact(), transform = tolower)

  expect_identical(spec$comparisons[[1]]$transform, tolower)

  skip_if_not_installed('duckdb')

  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- fake_1000
  spec_full <- il_spec() |>
    il_compare(first_name, cl_exact(), transform = tolower) |>
    il_compare(surname, cl_exact()) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(df, spec = spec_full, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  path <- tempfile(fileext = '.json')
  on.exit(unlink(path), add = TRUE)
  il_save(model, path)
  raw <- jsonlite::read_json(path, simplifyVector = FALSE)
  loaded <- il_load(path)

  expect_null(raw$comparisons[[1]]$comparison_description)
  expect_match(raw$comparisons[[1]]$comparison_levels[[1]]$sql_condition, 'LOWER')
  expect_null(loaded$spec$comparisons[[1]]$transform)
  expect_null(loaded$spec$comparisons[[2]]$transform)

  attached <- il_attach(loaded, df, con = con)
  pairs <- predict(attached, threshold = 0)

  expect_s3_class(pairs, 'il_compared')
  expect_gt(nrow(pairs), 0)
})

test_that('transform = tolower produces LOWER() in SQL gamma', {
  comp <- list(
    columns = 'name',
    method = structure(list(method = 'exact'), class = 'il_comparison_level'),
    transform = tolower
  )
  sql <- sql_gamma_case(comp, 'duckdb')
  expect_true(grepl('LOWER', sql))
  expect_true(grepl('LOWER\\(l\\."name"\\)', sql))
  expect_true(grepl('LOWER\\(r\\."name"\\)', sql))
})

test_that('transform = toupper produces UPPER() in SQL gamma', {
  comp <- list(
    columns = 'name',
    method = structure(list(method = 'jaro_winkler', thresholds = c(0.9, 0.7)),
      class = 'il_comparison_level'
    ),
    transform = toupper
  )
  sql <- sql_gamma_case(comp, 'duckdb')
  expect_true(grepl('UPPER', sql))
})

test_that('NULL transform leaves SQL unchanged', {
  comp <- list(
    columns = 'name',
    method = structure(list(method = 'exact'), class = 'il_comparison_level'),
    transform = NULL
  )
  sql <- sql_gamma_case(comp, 'duckdb')
  expect_false(grepl('LOWER|UPPER|TRIM', sql))
  expect_true(grepl('l\\."name"', sql))
})

test_that('custom transforms error on SQL gamma paths', {
  comp <- list(
    columns = 'name',
    method = structure(list(method = 'exact'), class = 'il_comparison_level'),
    transform = function(x) trimws(tolower(x))
  )
  expect_error(sql_gamma_case(comp, 'duckdb'), class = 'il_error_type')
})

test_that('transform applied R-side in compute_gamma_matrix', {
  comparisons <- list(
    list(
      columns = 'name',
      method = structure(list(method = 'exact'), class = 'il_comparison_level'),
      transform = tolower
    )
  )
  pairs <- data.frame(l_name = c('Alice', 'BOB'), r_name = c('ALICE', 'bob'))
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  # Both should be gamma = 1 (exact match after tolower)
  expect_equal(gamma_mat[1, 1], 1L, ignore_attr = TRUE)
  expect_equal(gamma_mat[2, 1], 1L, ignore_attr = TRUE)
})

test_that('il_compare rejects non-function transform', {
  spec <- il_spec()
  expect_error(
    il_compare(spec, name, cl_exact(), transform = 'tolower'),
    'transform'
  )
})
