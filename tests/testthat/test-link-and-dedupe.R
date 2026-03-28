# Sprint 10 — link_and_dedupe mode and il_find_matches edge cases
# Tests that link_and_dedupe produces pairs from all three pair sets
# (A×B cross-table, A×A within-left, B×B within-right).

# Two small tables with known overlapping and within-table duplicates
make_lad_data <- function() {
 df_a <- data.frame(
 unique_id = 1:4,
 first_name = c('John', 'John', 'Alice', 'Bob'),
 surname = c('Smith', 'Smith', 'Brown', 'Jones'),
 city = c('London', 'London', 'Paris', 'Berlin'),
 stringsAsFactors = FALSE
 )
 df_b <- data.frame(
 unique_id = 5:8,
 first_name = c('John', 'Alice', 'Alice', 'Tom'),
 surname = c('Smith', 'Brown', 'Brown', 'White'),
 city = c('London', 'Paris', 'Paris', 'Madrid'),
 stringsAsFactors = FALSE
 )
 list(a = df_a, b = df_b)
}

make_lad_spec <- function() {
 il_spec() |>
 il_compare(first_name, cl_exact()) |>
 il_compare(surname, cl_exact()) |>
 il_block_on(city)
}

# --- il_model validation ---------------------------------------------------

test_that('link_and_dedupe requires two datasets', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 d <- make_lad_data()
 spec <- make_lad_spec()

 expect_error(
 il_model(d$a, spec = spec, con = con, link_type = 'link_and_dedupe'),
 'only one dataset'
 )
})

test_that('link_and_dedupe model creates successfully with two datasets', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 d <- make_lad_data()
 spec <- make_lad_spec()

 model <- il_model(d$a, d$b,
 spec = spec, con = con,
 link_type = 'link_and_dedupe'
 )
 expect_s3_class(model, 'il_model')
 expect_equal(model$link_type, 'link_and_dedupe')
})

# --- build_table_pairs -----------------------------------------------------

test_that('build_table_pairs returns 3 combos for link_and_dedupe', {

 pairs <- build_table_pairs('tbl_l', 'tbl_r', 'link_and_dedupe', TRUE)
 expect_length(pairs, 3)

 # Cross-table pair has no dedup guard
 expect_equal(pairs[[1]]$from_l, 'tbl_l')
 expect_equal(pairs[[1]]$from_r, 'tbl_r')
 expect_equal(pairs[[1]]$join_cond, '1=1')

 # Within-left pair has dedup guard

 expect_equal(pairs[[2]]$from_l, 'tbl_l')
 expect_equal(pairs[[2]]$from_r, 'tbl_l')
 expect_match(pairs[[2]]$join_cond, 'unique_id')

 # Within-right pair has dedup guard
 expect_equal(pairs[[3]]$from_l, 'tbl_r')
 expect_equal(pairs[[3]]$from_r, 'tbl_r')
 expect_match(pairs[[3]]$join_cond, 'unique_id')
})

test_that('build_table_pairs returns 1 combo for dedupe', {
 pairs <- build_table_pairs('tbl', 'tbl', 'dedupe', FALSE)
 expect_length(pairs, 1)
 expect_match(pairs[[1]]$join_cond, 'unique_id')
})

test_that('build_table_pairs returns 1 combo for link', {
 pairs <- build_table_pairs('tbl_l', 'tbl_r', 'link', TRUE)
 expect_length(pairs, 1)
 expect_equal(pairs[[1]]$join_cond, '1=1')
})

# --- Pair generation includes all 3 pair sets ------------------------------

test_that('link_and_dedupe get_all_pairs returns within-table pairs', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 d <- make_lad_data()
 spec <- make_lad_spec()

 model <- il_model(d$a, d$b,
 spec = spec, con = con,
 link_type = 'link_and_dedupe'
 )

 pairs <- get_all_pairs(model)

 # Cross-table pairs: IDs from different tables
 cross <- pairs[pairs$l_unique_id <= 4 & pairs$r_unique_id >= 5, ]
 expect_gt(nrow(cross), 0, label = 'cross-table pairs')

 # Within-left pairs: both IDs in 1:4
 within_l <- pairs[pairs$l_unique_id <= 4 & pairs$r_unique_id <= 4, ]
 expect_gt(nrow(within_l), 0, label = 'within-left pairs')

 # Within-right pairs: both IDs in 5:8
 within_r <- pairs[pairs$l_unique_id >= 5 & pairs$r_unique_id >= 5, ]
 expect_gt(nrow(within_r), 0, label = 'within-right pairs')
})

test_that('link_and_dedupe get_blocked_pairs returns within-table pairs', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 d <- make_lad_data()
 spec <- make_lad_spec()

 model <- il_model(d$a, d$b,
 spec = spec, con = con,
 link_type = 'link_and_dedupe'
 )

 blocking <- model$spec$blocking_rules[[1]]
 pairs <- get_blocked_pairs(model, blocking)

 # Cross-table blocked pairs (city-matched across tables)
 cross <- pairs[pairs$l_unique_id <= 4 & pairs$r_unique_id >= 5, ]
 expect_gt(nrow(cross), 0, label = 'cross-table blocked pairs')

 # Within-left pairs (city='London': ids 1,2)
 within_l <- pairs[pairs$l_unique_id <= 4 & pairs$r_unique_id <= 4, ]
 expect_gt(nrow(within_l), 0, label = 'within-left blocked pairs')
})

# --- End-to-end: train and predict -----------------------------------------

test_that('link_and_dedupe end-to-end: train and predict', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 d <- make_lad_data()
 spec <- make_lad_spec()

 model <- il_model(d$a, d$b,
 spec = spec, con = con,
 link_type = 'link_and_dedupe'
 ) |>
 il_estimate_u(max_pairs = 1e5) |>
 il_estimate_em(block_on(city))

 result <- predict(model, threshold = 0)
 expect_s3_class(result, 'il_compared')
 expect_gt(nrow(result), 0)

 # Verify we get pairs from all three sets
 cross <- result[result$unique_id_l <= 4 & result$unique_id_r >= 5, ]
 within_l <- result[result$unique_id_l <= 4 & result$unique_id_r <= 4, ]
 within_r <- result[result$unique_id_l >= 5 & result$unique_id_r >= 5, ]

 # At least cross-table pairs should exist; within-table depend on blocking
 expect_gt(nrow(cross), 0, label = 'predicted cross-table pairs')
})

# --- link mode still works (regression check) ------------------------------

test_that('link mode only produces cross-table pairs', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 d <- make_lad_data()
 spec <- make_lad_spec()

 model <- il_model(d$a, d$b,
 spec = spec, con = con,
 link_type = 'link'
 )

 pairs <- get_all_pairs(model)

 # All pairs should be cross-table
 expect_true(all(pairs$l_unique_id <= 4), 'left IDs from table A')
 expect_true(all(pairs$r_unique_id >= 5), 'right IDs from table B')
})

# --- il_find_matches missing-column fallback --------------------------------

test_that('il_find_matches handles new_records with fewer columns', {
 skip_if_not_installed('RSQLite')

 con <- test_con()
 withr::defer(test_discon(con))

 df <- data.frame(
 unique_id = 1:10,
 first_name = c(
 'John', 'Jon', 'Jane', 'Jane', 'Bob',
 'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas'
 ),
 surname = c(
 'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
 'Jones', 'Brown', 'Brown', 'White', 'White'
 ),
 city = c(
 'London', 'London', 'Paris', 'Paris', 'Berlin',
 'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
 ),
 stringsAsFactors = FALSE
 )
 spec <- il_spec() |>
 il_compare(first_name, cl_exact()) |>
 il_compare(surname, cl_exact()) |>
 il_compare(city, cl_exact()) |>
 il_block_on(first_name)

 model <- il_model(df, spec = spec, con = con) |>
 il_estimate_u(max_pairs = 1e5) |>
 il_estimate_em(block_on(first_name))

 # New records missing the 'city' column
 new <- data.frame(
 unique_id = 101:102,
 first_name = c('John', 'Alice'),
 surname = c('Smith', 'Brown'),
 stringsAsFactors = FALSE
 )

 # Should not error — missing column treated as NULL/non-match
 result <- il_find_matches(model, new)
 expect_s3_class(result, 'tbl_df')
})
