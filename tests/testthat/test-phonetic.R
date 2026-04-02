# Tests for phonetic transform functions (il_soundex, il_metaphone, il_dmetaphone)

# --- R-side soundex computation -----------------------------------------------

test_that('il_soundex produces correct codes for known inputs', {
  expect_equal(il_soundex('Robert'), 'R163')
  expect_equal(il_soundex('Rupert'), 'R163')
  expect_equal(il_soundex('Smith'),  'S530')
  expect_equal(il_soundex('Smyth'),  'S530')
  expect_equal(il_soundex('Johnson'), 'J525')
  expect_equal(il_soundex('Jonson'),  'J525')
})

test_that('il_soundex is case-insensitive', {
  expect_equal(il_soundex('smith'), il_soundex('SMITH'))
  expect_equal(il_soundex('robert'), il_soundex('Robert'))
})

test_that('il_soundex handles NA and empty strings', {
  expect_true(is.na(il_soundex(NA_character_)))
  expect_true(is.na(il_soundex('')))
})

test_that('il_soundex vectorises over character input', {
  result <- il_soundex(c('Smith', 'Robert', 'Johnson'))
  expect_length(result, 3)
  expect_equal(result, c('S530', 'R163', 'J525'))
})

test_that('il_soundex pads short codes to 4 characters', {
  # "Lee" → L000
  expect_equal(nchar(il_soundex('Lee')), 4)
  expect_equal(il_soundex('Lee'), 'L000')
})

# --- il_metaphone / il_dmetaphone error on R-side ----------------------------

test_that('il_metaphone errors when called on an R vector', {
  expect_error(il_metaphone('Smith'), 'SQL transform')
})

test_that('il_dmetaphone errors when called on an R vector', {
  expect_error(il_dmetaphone('Smith'), 'SQL transform')
})

# --- is_phonetic_transform ---------------------------------------------------

test_that('is_phonetic_transform identifies phonetic functions', {
  expect_true(irelink:::is_phonetic_transform(il_soundex))
  expect_true(irelink:::is_phonetic_transform(il_metaphone))
  expect_true(irelink:::is_phonetic_transform(il_dmetaphone))
  expect_false(irelink:::is_phonetic_transform(tolower))
  expect_false(irelink:::is_phonetic_transform(toupper))
  expect_false(irelink:::is_phonetic_transform(NULL))
})

# --- SQL generation -----------------------------------------------------------

test_that('phonetic_transform_sql generates DuckDB soundex macro call', {
  sql <- irelink:::phonetic_transform_sql(il_soundex, 'l.name', 'duckdb')
  expect_equal(sql, 'il_soundex(l.name)')
})

test_that('phonetic_transform_sql generates PostgreSQL soundex call', {
  sql <- irelink:::phonetic_transform_sql(il_soundex, 'l.name', 'postgres')
  expect_equal(sql, 'soundex(l.name)')
})

test_that('phonetic_transform_sql generates PostgreSQL metaphone call', {
  sql <- irelink:::phonetic_transform_sql(il_metaphone, 'l.name', 'postgres')
  expect_equal(sql, 'metaphone(l.name, 10)')
})

test_that('phonetic_transform_sql generates PostgreSQL dmetaphone call', {
  sql <- irelink:::phonetic_transform_sql(il_dmetaphone, 'l.name', 'postgres')
  expect_equal(sql, 'dmetaphone(l.name)')
})

test_that('phonetic_transform_sql returns NULL for non-phonetic transforms', {
  expect_null(irelink:::phonetic_transform_sql(tolower, 'l.name', 'duckdb'))
  expect_null(irelink:::phonetic_transform_sql(NULL, 'l.name', 'duckdb'))
})

# --- sql_transform_col with phonetic transforms ------------------------------

test_that('sql_transform_col wraps column with phonetic SQL', {
  expect_equal(
    irelink:::sql_transform_col('l.name', il_soundex, 'duckdb'),
    'il_soundex(l.name)'
  )
  expect_equal(
    irelink:::sql_transform_col('r.name', il_soundex, 'postgres'),
    'soundex(r.name)'
  )
})

# --- Dialect validation -------------------------------------------------------

test_that('validate_phonetic_dialect rejects unsupported backends', {
  expect_error(
    irelink:::validate_phonetic_dialect('il_soundex', 'sqlite'),
    'sqlite'
  )
  expect_error(
    irelink:::validate_phonetic_dialect('il_metaphone', 'duckdb'),
    'duckdb'
  )
  expect_error(
    irelink:::validate_phonetic_dialect('il_dmetaphone', 'duckdb'),
    'duckdb'
  )
})

test_that('validate_phonetic_dialect accepts supported backends', {
  expect_silent(irelink:::validate_phonetic_dialect('il_soundex', 'duckdb'))
  expect_silent(irelink:::validate_phonetic_dialect('il_soundex', 'postgres'))
  expect_silent(irelink:::validate_phonetic_dialect('il_metaphone', 'postgres'))
  expect_silent(irelink:::validate_phonetic_dialect('il_dmetaphone', 'postgres'))
})

# --- Serialization (transform_to_name / name_to_transform) -------------------

test_that('phonetic transforms serialize and deserialize correctly', {
  expect_equal(irelink:::transform_to_name(il_soundex),    'il_soundex')
  expect_equal(irelink:::transform_to_name(il_metaphone),  'il_metaphone')
  expect_equal(irelink:::transform_to_name(il_dmetaphone), 'il_dmetaphone')

  expect_identical(irelink:::name_to_transform('il_soundex'),    il_soundex)
  expect_identical(irelink:::name_to_transform('il_metaphone'),  il_metaphone)
  expect_identical(irelink:::name_to_transform('il_dmetaphone'), il_dmetaphone)
})

# --- il_block_on / block_on with .transform -----------------------------------

test_that('il_block_on stores phonetic transform in rule', {
  spec <- il_spec() |>
    il_block_on(first_name, .transform = il_soundex)

  rule <- spec$blocking_rules[[1]]
  expect_identical(rule$transform, il_soundex)
  expect_s3_class(rule, 'il_blocking_rule')
})

test_that('block_on stores phonetic transform in rule', {
  rule <- block_on(first_name, .transform = il_soundex)
  expect_identical(rule$transform, il_soundex)
})

test_that('il_block_on rejects non-function .transform', {
  expect_error(
    il_spec() |> il_block_on(first_name, .transform = 'il_soundex'),
    class = 'il_error_type'
  )
})

test_that('block_on rejects non-function .transform', {
  expect_error(
    block_on(first_name, .transform = 'il_soundex'),
    class = 'il_error_type'
  )
})

# --- build_blocking_condition with phonetic transform -------------------------

test_that('build_blocking_condition applies soundex transform (DuckDB)', {
  sql <- irelink:::build_blocking_condition(
    columns = c('first_name', 'surname'),
    transform = il_soundex,
    dialect = 'duckdb'
  )
  expect_true(grepl('il_soundex\\(l\\.first_name\\)', sql))
  expect_true(grepl('il_soundex\\(r\\.first_name\\)', sql))
  expect_true(grepl('il_soundex\\(l\\.surname\\)', sql))
  expect_true(grepl('il_soundex\\(r\\.surname\\)', sql))
  expect_true(grepl('AND', sql))
})

test_that('build_blocking_condition applies soundex transform (PostgreSQL)', {
  sql <- irelink:::build_blocking_condition(
    columns = 'first_name',
    transform = il_soundex,
    dialect = 'postgres'
  )
  expect_true(grepl('soundex\\(l\\.first_name\\)', sql))
  expect_true(grepl('soundex\\(r\\.first_name\\)', sql))
})

test_that('build_blocking_condition without transform leaves columns bare', {
  sql <- irelink:::build_blocking_condition(columns = 'first_name')
  expect_equal(sql, 'l.first_name = r.first_name')
})

# --- print.il_spec shows transform label ------------------------------------

test_that('print.il_spec displays phonetic transform label', {
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_block_on(first_name, .transform = il_soundex)

  out <- capture.output(print(spec))
  combined <- paste(out, collapse = '\n')
  expect_true(grepl('il_soundex', combined))
})

# --- DuckDB macro registration & SQL-side soundex ----------------------------

test_that('register_phonetic_macros creates il_soundex in DuckDB', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  irelink:::register_phonetic_macros(con)

  # Confirm the macro works
  result <- DBI::dbGetQuery(con, "SELECT il_soundex('Smith') AS code")
  expect_equal(result$code, 'S530')
})

test_that('DuckDB il_soundex macro matches R-side for known pairs', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  irelink:::register_phonetic_macros(con)

  pairs <- data.frame(name = c('Smith', 'Smyth', 'Robert', 'Rupert',
                                'Johnson', 'Jonson', 'Lee', 'Stephen', 'Steven'))
  DBI::dbWriteTable(con, '__test_names', pairs, overwrite = TRUE)

  result <- DBI::dbGetQuery(con, 'SELECT name, il_soundex(name) AS code FROM __test_names')

  r_codes <- il_soundex(pairs$name)
  expect_equal(result$code, r_codes)
})

test_that('DuckDB il_soundex macro handles NULL', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  irelink:::register_phonetic_macros(con)

  result <- DBI::dbGetQuery(con, "SELECT il_soundex(NULL) AS code")
  expect_true(is.na(result$code))
})

# --- End-to-end blocking with phonetic transform (DuckDB) --------------------

test_that('il_block_on with il_soundex works in full pipeline', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(first_name, .transform = il_soundex)

  model <- il_model(fake_1000, spec = spec, con = con)

  # Count pairs using il_count_pairs (data + blocking rules)
  count <- il_count_pairs(
    fake_1000,
    block_on(first_name, .transform = il_soundex),
    con = con
  )

  # Soundex blocking should produce pairs
  expect_true(count$n_pairs[1] > 0)
})

test_that('block_on with il_soundex works in il_estimate_em', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(surname)

  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)

  # EM with phonetic training block
  model <- il_estimate_em(model, block_on(first_name, .transform = il_soundex))
  expect_s3_class(model, 'il_model')
})

# --- Save/load round-trip for phonetic blocking transforms -------------------

test_that('save/load preserves phonetic blocking transforms', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_compare(dob, cl_exact()) |>
    il_block_on(first_name, .transform = il_soundex) |>
    il_block_on(surname)

  model <- il_model(fake_1000, spec = spec, con = con)
  model <- il_estimate_u(model)
  model <- il_estimate_em(model, block_on(surname))

  path <- tempfile(fileext = '.json')
  on.exit(unlink(path), add = TRUE)
  il_save(model, path)
  loaded <- il_load(path)

  expect_identical(loaded$spec$blocking_rules[[1]]$transform, il_soundex)
  expect_null(loaded$spec$blocking_rules[[2]]$transform)
})
