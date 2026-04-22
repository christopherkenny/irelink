test_that('cl_levels assigns gamma -1 to null matches', {
  pairs <- data.frame(
    l_name = c(NA, 'John', NA),
    r_name = c(NA, NA, 'John'),
    stringsAsFactors = FALSE
  )
  comparisons <- list(list(
    columns = 'name',
    method = cl_levels(cl_null(), cl_exact(), cl_else())
  ))

  gamma <- compute_gamma_matrix(pairs, comparisons)

  expect_equal(unname(gamma[, 1]), c(-1L, -1L, -1L))
})

test_that('null gamma contributes zero match weight', {
  gamma_mat <- matrix(c(-1L, 0L, 1L),
    ncol = 1,
    dimnames = list(NULL, 'name')
  )
  mu <- list(
    m_levels = list(name = c(0.2, 0.8)),
    u_levels = list(name = c(0.8, 0.2))
  )

  weights <- score_gamma_matrix(gamma_mat, mu)

  expect_equal(weights[1], 0)
  expect_equal(weights[2], log2(0.2 / 0.8))
  expect_equal(weights[3], log2(0.8 / 0.2))
})
