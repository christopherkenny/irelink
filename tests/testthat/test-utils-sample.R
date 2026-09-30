test_that('hash_bucket_r() spreads sequential and string ids evenly', {
  expect_equal(mean(hash_bucket_r(1:20000, 100) < 10), 0.1, tolerance = 0.05)
  expect_equal(
    mean(hash_bucket_r(paste0('id', 1:20000), 100) < 25),
    0.25,
    tolerance = 0.05
  )
})

test_that('hash_bucket_r() is deterministic', {
  expect_identical(hash_bucket_r(c('a', 'b', 1), 1e9), hash_bucket_r(c('a', 'b', 1), 1e9))
})

test_that('il_sample_records() keeps the same records on repeat calls', {
  con <- test_con()
  withr::defer(test_discon(con))
  DBI::dbWriteTable(con, 'src', data.frame(unique_id = 1:500, x = 1))

  a <- il_sample_records(con, 'src', 3000, il_probe_sample_modulus)
  b <- il_sample_records(con, 'src', 3000, il_probe_sample_modulus)
  ids_a <- sort(DBI::dbGetQuery(con, paste('SELECT unique_id FROM', a))$unique_id)
  ids_b <- sort(DBI::dbGetQuery(con, paste('SELECT unique_id FROM', b))$unique_id)

  expect_identical(ids_a, ids_b)
  expect_equal(length(ids_a) / 500, 0.3, tolerance = 0.2)
})
