test_that("il_block_on stores .explode in rule", {
  spec <- il_spec() |>
    il_block_on(email, .explode = "email")
  rule <- spec$blocking_rules[[1]]
  expect_equal(rule$explode, "email")
})

test_that("il_block_on rejects non-character .explode", {
  expect_error(
    il_spec() |> il_block_on(email, .explode = 42),
    class = "il_error_type"
  )
})

test_that("block_on stores .explode in rule", {
  rule <- block_on(email, .explode = "email")
  expect_equal(rule$explode, "email")
})

test_that("block_on rejects non-character .explode", {
  expect_error(
    block_on(email, .explode = TRUE),
    class = "il_error_type"
  )
})

test_that("sql_explode_from returns table name when no explode cols", {
  result <- irelink:::sql_explode_from("my_tbl", NULL, "duckdb")
  expect_equal(result, "my_tbl")

  result2 <- irelink:::sql_explode_from("my_tbl", character(0), "duckdb")
  expect_equal(result2, "my_tbl")
})

test_that("sql_explode_from generates DuckDB UNNEST subquery", {
  result <- irelink:::sql_explode_from("my_tbl", "emails", "duckdb")
  expect_match(result, "EXCLUDE")
  expect_match(result, "UNNEST\\(emails\\) AS emails")
  expect_match(result, "FROM my_tbl")
})

test_that("sql_explode_from handles multiple explode cols in DuckDB", {
  result <- irelink:::sql_explode_from("t", c("emails", "phones"), "duckdb")
  expect_match(result, "UNNEST\\(emails\\) AS emails")
  expect_match(result, "UNNEST\\(phones\\) AS phones")
})

test_that("sql_explode_from generates PostgreSQL LATERAL UNNEST", {
  result <- irelink:::sql_explode_from("my_tbl", "tags", "postgres")
  expect_match(result, "CROSS JOIN LATERAL UNNEST")
  expect_match(result, "FROM my_tbl")
})

test_that("sql_explode_from warns for SQLite and returns table unchanged", {
  expect_warning(
    result <- irelink:::sql_explode_from("my_tbl", "arr", "sqlite"),
    "not supported for SQLite"
  )
  expect_equal(result, "my_tbl")
})

test_that("explode blocking works end-to-end with DuckDB arrays", {
  skip_if_not_installed("duckdb")
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  # Create table with an array column
  DBI::dbExecute(con, "
    CREATE TABLE arr_test (
      unique_id INTEGER,
      name VARCHAR,
      emails VARCHAR[]
    )
  ")
  DBI::dbExecute(con, "
    INSERT INTO arr_test VALUES
      (1, 'Alice', ['alice@a.com', 'alice@b.com']),
      (2, 'Bob',   ['bob@a.com']),
      (3, 'Carol', ['alice@b.com', 'carol@c.com'])
  ")

  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(emails, .explode = "emails")

  tbl_ref <- dplyr::tbl(con, "arr_test")
  model <- il_model(tbl_ref, spec = spec, con = con)

  # Verify the SQL generated includes UNNEST
  sql <- irelink:::build_gamma_query(model, model$spec$blocking_rules)
  expect_match(sql, "UNNEST")

  # Verify the UNNEST query actually runs and produces pairs
  result <- DBI::dbGetQuery(con, sql)
  expect_true(nrow(result) > 0)
  # Alice and Carol share alice@b.com — they should be paired
  pair_13 <- result[result$l_unique_id == 1 & result$r_unique_id == 3, ]
  expect_true(nrow(pair_13) > 0)

  DBI::dbExecute(con, "DROP TABLE arr_test")
})
