# Sprint 10 — Visualization: autoplot.il_model(), autoplot.il_compared()
# Translated from: test_charts.py

test_that('autoplot(model) returns a ggplot object', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  p <- ggplot2::autoplot(model)
  expect_s3_class(p, 'ggplot')
})

test_that('autoplot(pairs) returns a ggplot object', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  pairs <- predict(model, threshold = 0.5)

  p <- ggplot2::autoplot(pairs)
  expect_s3_class(p, 'ggplot')
})

test_that('autoplot(pairs, which = 1) includes prior and final waterfall steps', {
  skip_if_not_installed('RSQLite')

  con <- test_con()
  withr::defer(test_discon(con))

  df <- fake_1000
  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(first_name)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(first_name))

  pairs <- predict(model, threshold = 0.5)
  skip_if(nrow(pairs) == 0)

  wf <- il_waterfall(pairs, which = 1L)
  p <- ggplot2::autoplot(pairs, which = 1L)
  built <- ggplot2::ggplot_build(p)

  expect_s3_class(p, 'ggplot')
  expect_equal(wf$step[1], 'Prior')
  expect_equal(wf$step[nrow(wf)], 'Final')
  expect_equal(nrow(built$data[[1]]), nrow(wf))
})

test_that('autoplot(il_profile) orders values within each facet', {
  prof <- structure(
    tibble::tibble(
      column = c('first_name', 'surname', 'surname'),
      value = c('A', 'A', 'B'),
      n = c(100, 1, 10)
    ),
    class = c('il_profile', 'tbl_df', 'tbl', 'data.frame')
  )

  built <- ggplot2::ggplot_build(ggplot2::autoplot(prof))
  panel_map <- built$layout$layout[, c('PANEL', 'column')]
  surname_panel <- panel_map$PANEL[panel_map$column == 'surname']
  surname_rows <- built$data[[1]][built$data[[1]]$PANEL == surname_panel, ]

  expect_lt(
    surname_rows$x[surname_rows$y == 1],
    surname_rows$x[surname_rows$y == 10]
  )
})
