# Tutorial 05 — Predicting Results
# Translation of splink docs/demos/tutorials/05_Predicting_results.ipynb
# -----------------------------------------------------------------------
# Covers: prediction, clustering, threshold exploration

library(irelink)
library(duckdb)
library(DBI)

df <- il_demo("fake_1000")
con <- dbConnect(duckdb())

# Build and train model quickly
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

# Predict (splink: linker.inference.predict) --------------------------------
# Lower threshold casts a wide net
predictions <- predict(model, threshold = 0.2)
head(predictions, 5)

# Cluster (splink: cluster_pairwise_predictions_at_threshold) ---------------
clusters <- il_cluster(predictions, threshold = 0.5)
head(clusters, 5)

# splink: linker.misc.query_sql() — in R, use DBI directly
# DBI::dbGetQuery(con, "SELECT ...")

dbDisconnect(con, shutdown = TRUE)
