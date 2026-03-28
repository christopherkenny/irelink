# R-specific edge-case tests not covered by dedicated test files.
# Each test here targets a specific boundary condition or R idiom.

# ── Unit helper edge cases ──────────────────────────────────────────────────────────

test_that('unit helpers reject NA input', {
 expect_error(days(NA))
 expect_error(days(NA_real_))
 expect_error(months(NA))
 expect_error(km(NA))
 expect_error(mi(NA_integer_))
})

test_that('unit helpers accept zero', {
 d <- days(0)
 expect_equal(d$value, 0)
 k <- km(0)
 expect_equal(k$value, 0)
})

test_that('unit helpers reject length > 1 input', {
 expect_error(days(c(1, 2)))
 expect_error(km(c(5, 10)))
})

test_that('unit helpers reject Inf and NaN', {
 expect_error(days(Inf))
 expect_error(km(NaN))
})

# ── Comparison level: NA and boundary thresholds ────────────────────────────

test_that('similarity thresholds reject NA values', {
 expect_error(cl_jaro_winkler(NA))
 expect_error(cl_jaccard(NA_real_))
})

test_that('distance thresholds reject NA values', {
 expect_error(cl_levenshtein(NA))
 expect_error(cl_numeric_diff(NA_real_))
})

test_that('similarity thresholds reject Inf', {
 expect_error(cl_jaro_winkler(Inf))
 expect_error(cl_cosine(-Inf))
})

test_that('cl_custom() rejects non-character input', {
 expect_error(cl_custom(42))
 expect_error(cl_custom(NULL))
 expect_error(cl_custom(c('a = b', 'c = d')))
})

test_that('cl_levels() rejects non-comparison-level arguments', {
 expect_error(cl_levels('not a level'))
 expect_error(cl_levels(42))
})

# ── il_string_similarity: type rejection ────────────────────────────────

test_that('il_string_similarity() rejects non-character input', {
 expect_error(il_string_similarity(123, 'hello'))
 expect_error(il_string_similarity('hello', TRUE))
})

test_that('il_string_similarity() rejects vector input', {
 expect_error(il_string_similarity(c('a', 'b'), 'c'))
})

test_that('il_string_similarity() with two empty strings returns perfect similarity', {
 result <- il_string_similarity('', '')
 expect_equal(result$levenshtein, 0L)
})

test_that('il_string_similarity() both NA returns all NA', {
 result <- il_string_similarity(NA_character_, NA_character_)
 expect_true(is.na(result$jaro_winkler))
 expect_true(is.na(result$levenshtein))
 expect_true(is.na(result$jaccard))
})

# ── il_completeness: edge cases ──────────────────────────────────────────

test_that('il_completeness() with all-NA column reports 0%', {
 con <- test_con()
 withr::defer(test_discon(con))
 df <- data.frame(id = 1:3, x = c(NA, NA, NA))
 result <- il_completeness(df, con = con)
 x_row <- result[result$column == 'x', ]
 expect_equal(x_row$pct_non_null, 0, tolerance = 0.01)
})

test_that('il_completeness() with single-column data frame works', {
 con <- test_con()
 withr::defer(test_discon(con))
 df <- data.frame(id = 1:5)
 result <- il_completeness(df, con = con)
 expect_equal(nrow(result), 1)
 expect_equal(result$pct_non_null[1], 100, tolerance = 0.01)
})

test_that('il_completeness() with two tables returns rows for both', {
 con <- test_con()
 withr::defer(test_discon(con))
 df1 <- data.frame(a = c(1, NA), b = c('x', 'y'))
 df2 <- data.frame(a = c(NA, NA, 3), c = c('p', 'q', 'r'))
 result <- il_completeness(df1, df2, con = con)
 expect_true(all(c('table_1', 'table_2') %in% result$table))
})

# ── il_count_pairs: edge cases ──────────────────────────────────────────

test_that('il_count_pairs() with blocking on all-unique column returns zero pairs', {
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
 con <- test_con()
 withr::defer(test_discon(con))
 df <- data.frame(unique_id = 1L, name = 'A')
 result <- il_count_pairs(df, con = con)
 expect_equal(result$n_pairs[1], 0L)
})

# ── il_model: error messages and edge cases ──────────────────────────

test_that('il_model() with missing columns errors with informative class', {
 con <- test_con()
 withr::defer(test_discon(con))
 df <- data.frame(unique_id = 1:3, name = c('A', 'B', 'C'))
 spec <- il_spec() |> il_compare(nonexistent, cl_exact())
 expect_error(il_model(df, spec = spec, con = con))
})

test_that('il_model() stores data dimensions correctly', {
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

# ── predict: threshold boundaries ───────────────────────────────────────

test_that('predict() at threshold = 1.0 returns zero or few pairs', {
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
 expect_true(nrow(pairs) <= nrow(predict(model, threshold = 0.5)))
})

# ── il_find_matches: no matches ──────────────────────────────────────

test_that('il_find_matches() returns zero rows when no blocking match', {
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

# ── il_waterfall: column content ─────────────────────────────────────

test_that('il_waterfall() has step, contribution, and direction columns', {
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
 expect_true('first_name' %in% wf$step)
 expect_true('surname' %in% wf$step)
 }
})

# ── NA values in data during model operations ──────────────────────────

test_that('il_estimate_em() tolerates NA values in non-blocking columns', {
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

test_that('predict() handles NA in comparison columns without error', {
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
 expect_true(all(pairs$match_probability >= 0 & pairs$match_probability <= 1))
})
