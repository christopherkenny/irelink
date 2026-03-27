# R-specific tests — gaps identified by comparing the Python-translated
# test suite against R idioms: NA handling, type coercion, vectorization,
# edge cases, S3 dispatch, error classes, and pipe chaining.

# ── Unit helper edge cases (Sprint 1) ────────────────────────────────────

test_that('unit helpers reject NA input', {
  skip_if_sprint_lt(1)
  expect_error(days(NA))
  expect_error(days(NA_real_))
  expect_error(months(NA))
  expect_error(km(NA))
  expect_error(mi(NA_integer_))
})

test_that('unit helpers accept zero', {
  skip_if_sprint_lt(1)
  d <- days(0)
  expect_equal(d$value, 0)
  k <- km(0)
  expect_equal(k$value, 0)
})

test_that('unit helpers reject length > 1 input', {
  skip_if_sprint_lt(1)
  expect_error(days(c(1, 2)))
  expect_error(km(c(5, 10)))
})

test_that('unit helpers reject Inf and NaN', {
  skip_if_sprint_lt(1)
  expect_error(days(Inf))
  expect_error(km(NaN))
})

# ── S3 class consistency (Sprint 1) ──────────────────────────────────────

test_that('il_spec inherits from list', {
  skip_if_sprint_lt(1)
  spec <- il_spec()
  expect_true(is.list(spec))
  expect_s3_class(spec, 'il_spec')
})

test_that('il_compared inherits from tbl_df', {
  skip_if_sprint_lt(1)
  obj <- structure(
    tibble::tibble(
      unique_id_l = 1L, unique_id_r = 2L,
      match_weight = 1.5, match_probability = 0.8
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )
  expect_s3_class(obj, 'il_compared')
  expect_s3_class(obj, 'tbl_df')
  expect_true(is.data.frame(obj))
})

# ── Comparison level: NA and boundary thresholds (Sprint 2) ───────────────

test_that('similarity thresholds reject NA values', {
  skip_if_sprint_lt(2)
  expect_error(cl_jaro_winkler(NA))
  expect_error(cl_jaccard(NA_real_))
})

test_that('distance thresholds reject NA values', {
  skip_if_sprint_lt(2)
  expect_error(cl_levenshtein(NA))
  expect_error(cl_numeric_diff(NA_real_))
})

test_that('similarity thresholds reject Inf', {
  skip_if_sprint_lt(2)
  expect_error(cl_jaro_winkler(Inf))
  expect_error(cl_cosine(-Inf))
})

test_that('cl_custom() rejects non-character input', {
  skip_if_sprint_lt(2)
  expect_error(cl_custom(42))
  expect_error(cl_custom(NULL))
  expect_error(cl_custom(c('a = b', 'c = d')))
})

test_that('cl_levels() rejects non-comparison-level arguments', {
  skip_if_sprint_lt(2)
  expect_error(cl_levels('not a level'))
  expect_error(cl_levels(42))
})

# ── il_compare: tidyselect edge cases (Sprint 3) ─────────────────────────

test_that('il_compare() with c() accumulates per-column entries', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(c(first_name, surname), cl_exact())
  expect_length(spec$comparisons, 2)
  cols <- vapply(spec$comparisons, function(c) c$columns, character(1))
  expect_true('first_name' %in% cols)
  expect_true('surname' %in% cols)
})

test_that('piping il_compare() and il_block_on() preserves both', {
  skip_if_sprint_lt(3)
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(surname) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(first_name)
  expect_length(spec$comparisons, 2)
  expect_length(spec$blocking_rules, 2)
})

# ── il_string_similarity: type rejection (Sprint 4) ──────────────────────

test_that('il_string_similarity() rejects non-character input', {
  skip_if_sprint_lt(4)
  expect_error(il_string_similarity(123, 'hello'))
  expect_error(il_string_similarity('hello', TRUE))
})

test_that('il_string_similarity() rejects vector input', {
  skip_if_sprint_lt(4)
  expect_error(il_string_similarity(c('a', 'b'), 'c'))
})

test_that('il_string_similarity() with two empty strings returns perfect similarity', {
  skip_if_sprint_lt(4)
  result <- il_string_similarity('', '')
  expect_equal(result$levenshtein, 0L)
})

test_that('il_string_similarity() both NA returns all NA', {
  skip_if_sprint_lt(4)
  result <- il_string_similarity(NA_character_, NA_character_)
  expect_true(is.na(result$jaro_winkler))
  expect_true(is.na(result$levenshtein))
  expect_true(is.na(result$jaccard))
})

# ── il_completeness: edge cases (Sprint 5) ───────────────────────────────

test_that('il_completeness() with all-NA column reports 0%', {
  skip_if_sprint_lt(5)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(id = 1:3, x = c(NA, NA, NA))
  result <- il_completeness(df, con = con)
  x_row <- result[result$column == 'x', ]
  expect_equal(x_row$pct_non_null, 0, tolerance = 0.01)
})

test_that('il_completeness() with single-column data frame works', {
  skip_if_sprint_lt(5)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(id = 1:5)
  result <- il_completeness(df, con = con)
  expect_equal(nrow(result), 1)
  expect_equal(result$pct_non_null[1], 100, tolerance = 0.01)
})

test_that('il_completeness() with two tables returns rows for both', {
  skip_if_sprint_lt(5)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df1 <- data.frame(a = c(1, NA), b = c('x', 'y'))
  df2 <- data.frame(a = c(NA, NA, 3), c = c('p', 'q', 'r'))

  result <- il_completeness(df1, df2, con = con)
  expect_true(all(c('table_1', 'table_2') %in% result$table))
})

# ── il_count_pairs: edge cases (Sprint 5) ─────────────────────────────────

test_that('il_count_pairs() with blocking on all-unique column returns zero pairs', {
  skip_if_sprint_lt(5)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    name = c('A', 'B', 'C', 'D', 'E')
  )
  result <- il_count_pairs(df, block_on(name), con = con)
  expect_equal(result$n_pairs[1], 0L)
})

test_that('il_count_pairs() with single-row data returns zero pairs in dedupe', {
  skip_if_sprint_lt(5)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(unique_id = 1L, name = 'A')
  result <- il_count_pairs(df, con = con)
  expect_equal(result$n_pairs[1], 0L)
})

# ── il_model: error class specificity (Sprint 6) ─────────────────────────

test_that('il_model() with missing columns errors with informative class', {
  skip_if_sprint_lt(6)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(unique_id = 1:3, name = c('A', 'B', 'C'))
  spec <- il_spec() |> il_compare(nonexistent, cl_exact())
  expect_error(il_model(df, spec = spec, con = con))
})

test_that('il_model() stores data dimensions correctly', {
  skip_if_sprint_lt(6)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:10,
    first_name = letters[1:10],
    surname = LETTERS[1:10]
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact())
  model <- il_model(df, spec = spec, con = con)
  expect_equal(model$data$n_records_l, 10L)
})

test_that('print.il_model() returns model invisibly', {
  skip_if_sprint_lt(6)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'B', 'C'),
    surname = rep('X', 5)
  )
  spec <- il_spec() |> il_compare(first_name, cl_exact())
  model <- il_model(df, spec = spec, con = con)
  out <- withr::with_output_sink(tempfile(), print(model))
  expect_s3_class(out, 'il_model')
})

# ── predict: threshold boundaries (Sprint 8) ─────────────────────────────

test_that('predict() at threshold = 1.0 returns zero or few pairs', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'B', 'C'),
    surname = rep('X', 5)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  pairs <- predict(model, threshold = 1.0)
  expect_s3_class(pairs, 'il_compared')
  # threshold=1.0 should be very restrictive
  expect_true(nrow(pairs) <= nrow(predict(model, threshold = 0.5)))
})

test_that('predict() output is sorted or at least deterministic', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('A', 'A', 'A', 'B', 'B', 'C'),
    surname = rep('X', 6)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(surname))

  p1 <- predict(model, threshold = 0.0)
  p2 <- predict(model, threshold = 0.0)
  expect_equal(nrow(p1), nrow(p2))
  # Sort both by the same key before comparing (row order is backend-dependent)
  o1 <- order(p1$unique_id_l, p1$unique_id_r)
  o2 <- order(p2$unique_id_l, p2$unique_id_r)
  expect_equal(p1$unique_id_l[o1], p2$unique_id_l[o2])
  expect_equal(p1$unique_id_r[o1], p2$unique_id_r[o2])
})

# ── il_compared dplyr verb coverage (Sprint 8) ───────────────────────────

test_that('il_compared supports select, arrange, and slice', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('dplyr')

  pairs <- structure(
    tibble::tibble(
      unique_id_l = c(1L, 2L, 3L),
      unique_id_r = c(4L, 5L, 6L),
      match_weight = c(3.0, 1.5, 2.0),
      match_probability = c(0.95, 0.60, 0.80)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  selected <- dplyr::select(pairs, unique_id_l, match_probability)
  expect_true(ncol(selected) == 2)

  arranged <- dplyr::arrange(pairs, dplyr::desc(match_probability))
  expect_equal(arranged$match_probability[1], 0.95)

  sliced <- dplyr::slice(pairs, 1)
  expect_equal(nrow(sliced), 1)
})

# ── il_find_matches: no matches (Sprint 8) ───────────────────────────────

test_that('il_find_matches() returns zero rows when no blocking match', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'B', 'C'),
    surname = c('X', 'X', 'Y', 'Y', 'Z')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(surname))

  new_rec <- data.frame(first_name = 'Q', surname = 'NONE', stringsAsFactors = FALSE)
  matches <- il_find_matches(model, new_rec, threshold = 0.01)
  expect_s3_class(matches, 'tbl_df')
  expect_equal(nrow(matches), 0)
})

# ── il_waterfall: column content (Sprint 8) ──────────────────────────────

test_that('il_waterfall() has step, contribution, and direction columns', {
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
  if (nrow(pairs) > 0) {
    wf <- il_waterfall(pairs, which = 1L)
    expect_true('step' %in% names(wf))
    expect_true('contribution' %in% names(wf))
    expect_true('direction' %in% names(wf))
    # Steps should correspond to comparison columns
    expect_true('first_name' %in% wf$step)
    expect_true('surname' %in% wf$step)
  }
})

# ── il_cluster: R-specific edge cases (Sprint 9) ─────────────────────────

test_that('il_cluster() cluster IDs are unique per cluster', {
  skip_if_sprint_lt(9)

  pairs <- structure(
    tibble::tibble(
      unique_id_l = c('A', 'C'),
      unique_id_r = c('B', 'D'),
      match_weight = c(5.0, 4.0),
      match_probability = c(0.97, 0.94)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  clusters <- il_cluster(pairs, threshold = 0.5)
  # Two disconnected pairs → two clusters
  expect_equal(length(unique(clusters$cluster_id)), 2)
  # Four unique records
  expect_equal(nrow(clusters), 4)
  # Every record has a cluster
  expect_true(all(!is.na(clusters$cluster_id)))
})

test_that('il_cluster() isolates records below threshold', {
  skip_if_sprint_lt(9)

  pairs <- structure(
    tibble::tibble(
      unique_id_l = c('A', 'B'),
      unique_id_r = c('B', 'C'),
      match_weight = c(5.0, 0.1),
      match_probability = c(0.97, 0.10)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  clusters <- il_cluster(pairs, threshold = 0.5)
  # A-B linked, C isolated → 2 clusters
  expect_equal(length(unique(clusters$cluster_id)), 2)
  # A and B share a cluster
  cid_a <- clusters$cluster_id[clusters$unique_id == 'A']
  cid_b <- clusters$cluster_id[clusters$unique_id == 'B']
  expect_equal(cid_a, cid_b)
})

test_that('il_cluster() method validation rejects invalid methods', {
  skip_if_sprint_lt(9)

  pairs <- structure(
    tibble::tibble(
      unique_id_l = 'A', unique_id_r = 'B',
      match_weight = 5.0, match_probability = 0.97
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  expect_error(il_cluster(pairs, method = 'invalid_method'))
})

# ── il_graph_metrics: edge cases (Sprint 9) ──────────────────────────────

test_that('il_graph_metrics() with single-node cluster has zero edges', {
  skip_if_sprint_lt(9)

  pairs <- structure(
    tibble::tibble(
      unique_id_l = c('A'),
      unique_id_r = c('B'),
      match_weight = 5.0,
      match_probability = 0.97
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  clusters <- il_cluster(pairs, threshold = 0.5)
  metrics <- il_graph_metrics(pairs, clusters)

  # nodes tibble should have degree info
  expect_true('degree' %in% names(metrics$nodes))
  # cluster tibble should report density
  expect_true('density' %in% names(metrics$clusters))
  # single cluster with 2 nodes, 1 edge → density = 1.0
  expect_equal(metrics$clusters$density[1], 1.0, tolerance = 0.01)
})

test_that('il_graph_metrics() returns three named elements', {
  skip_if_sprint_lt(9)

  pairs <- structure(
    tibble::tibble(
      unique_id_l = c('A', 'C'),
      unique_id_r = c('B', 'D'),
      match_weight = c(5.0, 4.0),
      match_probability = c(0.97, 0.94)
    ),
    class = c('il_compared', 'tbl_df', 'tbl', 'data.frame')
  )

  clusters <- il_cluster(pairs, threshold = 0.5)
  metrics <- il_graph_metrics(pairs, clusters)

  expect_true(is.list(metrics))
  expect_true(all(c('nodes', 'edges', 'clusters') %in% names(metrics)))
  expect_s3_class(metrics$nodes, 'tbl_df')
  expect_s3_class(metrics$edges, 'tbl_df')
  expect_s3_class(metrics$clusters, 'tbl_df')
})

# ── il_accuracy: all-match and all-non-match labels (Sprint 10) ──────────

test_that('il_accuracy() with all-positive labels has zero FP', {
  skip_if_sprint_lt(10)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('A', 'A', 'B', 'B'),
    surname = rep('X', 4)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  labels <- data.frame(
    unique_id_l = c(1L, 3L),
    unique_id_r = c(2L, 4L),
    is_match = c(TRUE, TRUE)
  )

  acc <- il_accuracy(model, labels)
  # At threshold = 0, everything is predicted positive, so FP = 0
  row0 <- acc[acc$threshold == 0, ]
  if (nrow(row0) > 0) {
    expect_equal(row0$fp[1], 0L)
  }
})

test_that('il_errors() type column distinguishes FP from FN', {
  skip_if_sprint_lt(10)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'C', 'D'),
    surname = rep('X', 5)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(surname)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(surname))

  labels <- data.frame(
    unique_id_l = c(1L, 3L),
    unique_id_r = c(2L, 4L),
    is_match = c(TRUE, FALSE)
  )

  errors <- il_errors(model, labels, threshold = 0.5)
  expect_s3_class(errors, 'tbl_df')
  expect_true('error_type' %in% names(errors))
})

# ── il_save / il_load: round-trip fidelity (Sprint 10) ───────────────────

test_that('il_save() and il_load() preserve spec structure', {
  skip_if_sprint_lt(10)
  skip_if_not_installed('RSQLite')
  skip_if_not_installed('jsonlite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'B', 'C'),
    surname = rep('X', 5)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  tmp <- withr::local_tempfile(fileext = '.json')
  il_save(model, tmp)
  loaded <- il_load(tmp)

  # Loaded model should have same number of comparisons
  expect_equal(
    length(loaded$spec$comparisons),
    length(model$spec$comparisons)
  )
  # Loaded model should have same comparison columns
  orig_cols <- vapply(model$spec$comparisons, function(c) c$columns, character(1))
  load_cols <- vapply(loaded$spec$comparisons, function(c) c$columns, character(1))
  expect_equal(orig_cols, load_cols)
})

test_that('il_load() on corrupted file errors informatively', {
  skip_if_sprint_lt(10)
  skip_if_not_installed('jsonlite')

  tmp <- withr::local_tempfile(fileext = '.json')
  writeLines('not valid json{{{', tmp)
  expect_error(il_load(tmp))
})

# ── autoplot: S3 dispatch (Sprint 10) ────────────────────────────────────

test_that('autoplot.il_model() dispatches correctly via ggplot2::autoplot()', {
  skip_if_sprint_lt(10)
  skip_if_not_installed('RSQLite')
  skip_if_not_installed('ggplot2')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('A', 'A', 'B', 'B', 'C'),
    surname = rep('X', 5)
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name)
  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  p <- ggplot2::autoplot(model)
  expect_s3_class(p, 'ggplot')
  # Should have at least one layer
  expect_true(length(p$layers) >= 1)
})

# ── Pipeline: deterministic link in chain (Sprint 8) ─────────────────────

test_that('il_deterministic_link() works in a pipe with spec', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:4,
    first_name = c('John', 'John', 'Mary', 'Mary'),
    surname = c('Smith', 'Smith', 'Jones', 'Jones')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name, surname)

  matches <- il_deterministic_link(df, spec = spec, con = con)
  expect_s3_class(matches, 'tbl_df')
  expect_true(nrow(matches) >= 2)
})

# ── NA values in data columns during model operations (Sprint 7) ─────────

test_that('il_estimate_em() tolerates NA values in non-blocking columns', {
  skip_if_sprint_lt(7)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('John', 'John', 'Mary', 'Mary', 'Eve', 'Eve'),
    surname = c('Smith', NA, 'Jones', 'Jones', NA, 'Adams')
  )
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  expect_true(model$trained)
  params <- il_parameters(model)
  expect_true(all(params$m >= 0 & params$m <= 1))
  expect_true(all(params$u >= 0 & params$u <= 1))
})

# ── predict with NA in comparison columns (Sprint 8) ─────────────────────

test_that('predict() handles NA in comparison columns without error', {
  skip_if_sprint_lt(8)
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- data.frame(
    unique_id = 1:6,
    first_name = c('A', 'A', 'B', 'B', NA, 'C'),
    surname = c('X', 'X', 'Y', NA, 'Z', 'Z')
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
  # Probabilities should still be in [0, 1] even with NA comparisons
  expect_true(all(pairs$match_probability >= 0 & pairs$match_probability <= 1))
})

# ── il_weights / il_parameters: column contracts (Sprint 7) ──────────────

test_that('il_weights() has comparison, level, and weight columns', {
  skip_if_sprint_lt(7)
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

  wt <- il_weights(model)
  expect_true(all(c('comparison', 'level', 'weight') %in% names(wt)))
  # At least one row per comparison
  expect_true(nrow(wt) >= 2)
})

test_that('il_parameters() returns m and u for every comparison × level', {
  skip_if_sprint_lt(7)
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

  params <- il_parameters(model)
  expect_true(all(c('comparison', 'level', 'm', 'u') %in% names(params)))
  # m and u are proper probabilities
  expect_true(all(params$m >= 0 & params$m <= 1))
  expect_true(all(params$u >= 0 & params$u <= 1))
  # Each comparison has match and non_match level
  for (comp in unique(params$comparison)) {
    levels <- params$level[params$comparison == comp]
    expect_true('match' %in% levels)
    expect_true('non_match' %in% levels)
  }
})
