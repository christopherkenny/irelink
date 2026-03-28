# Sprint 10 — Visualization: autoplot.il_model(), autoplot.il_compared()
# Translated from: test_charts.py

test_that('autoplot(model) returns a ggplot object', {
 skip_if_not_installed('RSQLite')
 skip_if_not_installed('ggplot2')

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
 skip_if_not_installed('ggplot2')

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
