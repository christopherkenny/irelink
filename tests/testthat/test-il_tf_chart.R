test_that('il_tf_chart rejects non-model', {
  expect_error(
    il_tf_chart('not_a_model', 'col'),
    class = 'il_error_type'
  )
})

test_that('il_tf_chart rejects non-string col', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)
  spec <- il_spec() |>
    il_compare(first_name, cl_exact(term_frequency = TRUE))
  model <- il_model(fake_1000, spec = spec, con = con)
  expect_error(il_tf_chart(model, 42), class = 'il_error_type')
})

test_that('il_tf_chart returns a ggplot', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  spec <- il_spec() |>
    il_compare(first_name, cl_exact(term_frequency = TRUE))
  model <- il_model(fake_1000, spec = spec, con = con)
  p <- il_tf_chart(model, 'first_name')
  expect_s3_class(p, 'ggplot')
})

test_that('il_tf_chart quotes non-syntactic TF column names', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)

  df <- data.frame(unique_id = 1:4, check.names = FALSE)
  df[['first name']] <- c('A', 'A', 'B', 'B')

  spec <- il_spec() |>
    il_compare(all_of('first name'), cl_exact(term_frequency = TRUE))
  model <- il_model(df, spec = spec, con = con)

  p <- il_tf_chart(model, 'first name')
  expect_s3_class(p, 'ggplot')
})

test_that('il_tf_chart errors for col without TF table', {
  con <- test_con()
  on.exit(test_discon(con), add = TRUE)
  spec <- il_spec() |>
    il_compare(first_name, cl_exact())
  model <- il_model(fake_1000, spec = spec, con = con)
  expect_error(il_tf_chart(model, 'first_name'), class = 'il_error_type')
})

test_that('autoplot.il_string_similarity returns a ggplot', {
  sim <- il_string_similarity('John', 'Jon')
  expect_s3_class(sim, 'il_string_similarity')
  p <- ggplot2::autoplot(sim)
  expect_s3_class(p, 'ggplot')
})

test_that('autoplot.il_string_similarity handles NA inputs', {
  sim <- il_string_similarity(NA_character_, 'Jon')
  expect_s3_class(sim, 'il_string_similarity')
  # Should handle NAs gracefully (plot with NA values)
  p <- ggplot2::autoplot(sim)
  expect_s3_class(p, 'ggplot')
})
