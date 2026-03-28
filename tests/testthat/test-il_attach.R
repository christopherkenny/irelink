# Sprint 10 — il_attach(): reattach saved models to fresh data
# Tests the production workflow: train → save → load → attach → predict

# Helper: small trained model for reuse tests
make_attach_model <- function(con) {
 df <- data.frame(
 unique_id = 1:20,
 first_name = c(
 'John', 'Jon', 'Jane', 'Jane', 'Bob',
 'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
 'John', 'Jon', 'Jane', 'Janet', 'Bob',
 'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
 ),
 surname = c(
 'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
 'Jones', 'Brown', 'Brown', 'White', 'White',
 'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
 'Jones', 'Brown', 'Browne', 'White', 'White'
 ),
 stringsAsFactors = FALSE
 )

 spec <- il_spec() |>
 il_compare(first_name, cl_exact()) |>
 il_compare(surname, cl_exact()) |>
 il_block_on(first_name)

 il_model(df, spec = spec, con = con) |>
 il_estimate_u(max_pairs = 1e5) |>
 il_estimate_em(block_on(first_name))
}

# --- Basic il_attach() usage -----------------------------------------------

test_that('il_attach() returns a valid il_model', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 model <- make_attach_model(con)

 # Save and load
 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)
 expect_null(loaded$con)

 # Attach to fresh data + connection
 con2 <- test_con()
 withr::defer(test_discon(con2))

 new_df <- data.frame(
 unique_id = 101:120,
 first_name = c(
 'John', 'Jon', 'Jane', 'Janet', 'Bob',
 'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
 'John', 'Jon', 'Jane', 'Janet', 'Bob',
 'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
 ),
 surname = c(
 'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
 'Jones', 'Brown', 'Brown', 'White', 'White',
 'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
 'Jones', 'Brown', 'Browne', 'White', 'White'
 ),
 stringsAsFactors = FALSE
 )

 attached <- il_attach(loaded, new_df, con = con2)

 expect_s3_class(attached, 'il_model')
 expect_true(attached$trained)
 expect_false(is.null(attached$con))
})

# --- Parameters are preserved -----------------------------------------------

test_that('il_attach() preserves trained parameters', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))
 model <- make_attach_model(con)
 orig_params <- il_parameters(model)

 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 new_df <- data.frame(
 unique_id = 1:10,
 first_name = c(
 'John', 'Jon', 'Jane', 'Bob', 'Alice',
 'Tom', 'Eve', 'Sam', 'Pat', 'Kim'
 ),
 surname = c(
 'Smith', 'Smith', 'Doe', 'Jones', 'Brown',
 'White', 'Adams', 'Clark', 'Davis', 'Evans'
 ),
 stringsAsFactors = FALSE
 )

 attached <- il_attach(loaded, new_df, con = con2)
 new_params <- il_parameters(attached)

 expect_equal(orig_params$m, new_params$m, tolerance = 1e-6)
 expect_equal(orig_params$u, new_params$u, tolerance = 1e-6)
})

# --- Predict works on attached model ----------------------------------------

test_that('predict() works on attached model', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))
 model <- make_attach_model(con)

 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 new_df <- data.frame(
 unique_id = 1:10,
 first_name = c(
 'John', 'John', 'Jane', 'Jane', 'Bob',
 'Bob', 'Alice', 'Alice', 'Tom', 'Tom'
 ),
 surname = c(
 'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
 'Jones', 'Brown', 'Brown', 'White', 'White'
 ),
 stringsAsFactors = FALSE
 )

 attached <- il_attach(loaded, new_df, con = con2)
 pairs <- predict(attached, threshold = 0)

 expect_s3_class(pairs, 'il_compared')
 expect_gt(nrow(pairs), 0)
 expect_true(all(c('match_weight', 'match_probability') %in% names(pairs)))
})

# --- Warm-start retraining on new data --------------------------------------

test_that('il_estimate_em() works on attached model (warm start)', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))
 model <- make_attach_model(con)
 orig_params <- il_parameters(model)

 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 # Completely different data
 new_df <- data.frame(
 unique_id = 1:20,
 first_name = c(
 'Liam', 'Liam', 'Emma', 'Emma', 'Noah',
 'Olivia', 'Olivia', 'Elijah', 'Ava', 'Ava',
 'James', 'James', 'Sophia', 'Sophia', 'Lucas',
 'Mia', 'Mia', 'Mason', 'Harper', 'Harper'
 ),
 surname = c(
 'Wilson', 'Wilson', 'Moore', 'Moore', 'Taylor',
 'Anderson', 'Anderson', 'Thomas', 'Jackson', 'Jackson',
 'Wilson', 'Wilson', 'Moore', 'Moore', 'Taylor',
 'Anderson', 'Anderson', 'Thomas', 'Jackson', 'Jackson'
 ),
 stringsAsFactors = FALSE
 )

 attached <- il_attach(loaded, new_df, con = con2)

 # Retrain — should not error, and should update parameters
 retrained <- il_estimate_em(attached, block_on(first_name))
 expect_true(retrained$trained)
 new_params <- il_parameters(retrained)

 # Parameters should exist and be numeric

 expect_type(new_params$m, 'double')
 expect_type(new_params$u, 'double')
})

# --- il_find_matches on attached model --------------------------------------

test_that('il_find_matches() works on attached model', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))
 model <- make_attach_model(con)

 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 existing_df <- data.frame(
 unique_id = 1:10,
 first_name = c(
 'John', 'Jon', 'Jane', 'Bob', 'Alice',
 'Tom', 'Eve', 'Sam', 'Pat', 'Kim'
 ),
 surname = c(
 'Smith', 'Smith', 'Doe', 'Jones', 'Brown',
 'White', 'Adams', 'Clark', 'Davis', 'Evans'
 ),
 stringsAsFactors = FALSE
 )

 attached <- il_attach(loaded, existing_df, con = con2)

 query <- data.frame(
 first_name = c('John', 'Jane'),
 surname = c('Smith', 'Doe'),
 stringsAsFactors = FALSE
 )

 result <- il_find_matches(attached, query, threshold = 0)
 expect_s3_class(result, 'tbl_df')
})

# --- Link mode with two tables ---------------------------------------------

test_that('il_attach() works with two-table link mode', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 df_a <- data.frame(
 unique_id = 1:5,
 first_name = c('John', 'Jane', 'Bob', 'Alice', 'Tom'),
 surname = c('Smith', 'Doe', 'Jones', 'Brown', 'White'),
 stringsAsFactors = FALSE
 )
 df_b <- data.frame(
 unique_id = 6:10,
 first_name = c('Jon', 'Janet', 'Bobby', 'Alicia', 'Thomas'),
 surname = c('Smith', 'Doe', 'Jones', 'Brown', 'White'),
 stringsAsFactors = FALSE
 )

 spec <- il_spec() |>
 il_compare(first_name, cl_exact()) |>
 il_compare(surname, cl_exact()) |>
 il_block_on(surname)

 model <- il_model(df_a, df_b, spec = spec, con = con, link_type = 'link') |>
 il_estimate_u(max_pairs = 1e5) |>
 il_estimate_em(block_on(surname))

 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 # New pair of tables
 new_a <- data.frame(
 unique_id = 11:15,
 first_name = c('Liam', 'Emma', 'Noah', 'Olivia', 'Elijah'),
 surname = c('Wilson', 'Moore', 'Taylor', 'Anderson', 'Thomas'),
 stringsAsFactors = FALSE
 )
 new_b <- data.frame(
 unique_id = 16:20,
 first_name = c('Liam', 'Emma', 'Noah', 'Olivia', 'Elijah'),
 surname = c('Wilson', 'Moore', 'Taylor', 'Anderson', 'Thomas'),
 stringsAsFactors = FALSE
 )

 attached <- il_attach(loaded, new_a, new_b, con = con2)
 expect_equal(attached$link_type, 'link')

 pairs <- predict(attached, threshold = 0)
 expect_s3_class(pairs, 'il_compared')
})

# --- Validation errors ------------------------------------------------------

test_that('il_attach() errors on zero-row data', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))
 model <- make_attach_model(con)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 empty <- data.frame(
 unique_id = integer(0), first_name = character(0),
 surname = character(0), stringsAsFactors = FALSE
 )

 expect_error(il_attach(model, empty, con = con2), 'zero-row')
})

test_that('il_attach() errors on missing columns', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))
 model <- make_attach_model(con)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 bad_df <- data.frame(
 unique_id = 1:3,
 first_name = c('A', 'B', 'C'),
 stringsAsFactors = FALSE
 )

 expect_error(il_attach(model, bad_df, con = con2), 'surname')
})

test_that('il_attach() errors when link model gets one table', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 df_a <- data.frame(
 unique_id = 1:3, first_name = c('A', 'B', 'C'),
 surname = c('X', 'Y', 'Z'), stringsAsFactors = FALSE
 )
 df_b <- data.frame(
 unique_id = 4:6, first_name = c('D', 'E', 'F'),
 surname = c('X', 'Y', 'Z'), stringsAsFactors = FALSE
 )

 spec <- il_spec() |>
 il_compare(first_name, cl_exact()) |>
 il_compare(surname, cl_exact()) |>
 il_block_on(surname)

 model <- il_model(df_a, df_b, spec = spec, con = con, link_type = 'link') |>
 il_estimate_u(max_pairs = 1e5) |>
 il_estimate_em(block_on(surname))

 tmp <- withr::local_tempfile(fileext = '.json')
 il_save(model, tmp)
 loaded <- il_load(tmp)

 con2 <- test_con()
 withr::defer(test_discon(con2))

 expect_error(
 il_attach(loaded, df_a, con = con2),
 'only one dataset'
 )
})
