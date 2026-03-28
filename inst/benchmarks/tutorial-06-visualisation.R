# Tutorial 06 — Visualising Predictions
# Translation of splink docs/demos/tutorials/06_Visualising_predictions.ipynb
# -----------------------------------------------------------------------
# Covers: waterfall charts, prediction inspection
#
# NOTE (interactive graphics): splink's comparison_viewer_dashboard() and
# cluster_studio_dashboard() produce standalone interactive HTML files.
# irelink does not replicate these interactive dashboards.
# Instead, use autoplot() and il_waterfall() for static equivalents.

library(irelink)
library(duckdb)
library(DBI)
library(ggplot2)

df <- il_demo("fake_1000")
con <- dbConnect(duckdb())

spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_levenshtein(1)) |>
  il_compare(city, cl_exact(term_frequency = TRUE)) |>
  il_compare(email, cl_email()) |>
  il_block_on(first_name) |>
  il_block_on(surname)

model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model, max_pairs = 5e5)
model <- il_estimate_em(model, block_on(first_name, surname))
model <- il_estimate_em(model, block_on(dob))

predictions <- predict(model, threshold = 0.2)

# Match weight distribution (splink: histogram of match_probability)
autoplot(predictions)

# Waterfall chart (splink: linker.visualisations.waterfall_chart) ----------
# Show per-comparison weight contributions for a single pair
wf <- il_waterfall(predictions, which = 1)
print(wf)

# Static waterfall visualisation
autoplot(predictions, which = 1)

# Cluster and inspect
clusters <- il_cluster(predictions, threshold = 0.5)

# NOTE: splink's comparison_viewer_dashboard() and cluster_studio_dashboard()
# are interactive HTML tools. These are out of scope for irelink.
# Use standard R tools (DT::datatable, shiny) for interactive exploration.

dbDisconnect(con, shutdown = TRUE)
