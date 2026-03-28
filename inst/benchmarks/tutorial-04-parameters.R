# Tutorial 04 — Estimating Model Parameters
# Translation of splink docs/demos/tutorials/04_Estimating_model_parameters.ipynb
# -----------------------------------------------------------------------
# Covers: comparison definition, settings, prior estimation,
#         u estimation, EM training, visualization, model save

library(irelink)
library(duckdb)
library(DBI)
library(ggplot2)

df <- il_demo("fake_1000")
con <- dbConnect(duckdb())

# Define comparisons (splink: SettingsCreator + comparison_library) --------
spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_levenshtein(1)) |>
  il_compare(city, cl_exact(term_frequency = TRUE)) |>
  il_compare(email, cl_email()) |>
  il_block_on(first_name) |>
  il_block_on(surname) |>
  il_block_on(
    city,
    .where = "substr(l.first_name, 1, 1) = substr(r.first_name, 1, 1)"
  )

# Create model (splink: Linker) -------------------------------------------
model <- il_model(df, spec = spec, con = con)
print(model)

# Estimate prior (splink: estimate_probability_two_random_records_match) ---
# Uses deterministic rules with fuzzy SQL conditions
model <- il_estimate_prior(
  model,
  block_on(first_name, .where = "levenshtein(l.dob, r.dob) <= 1"),
  block_on(surname, .where = "levenshtein(l.dob, r.dob) <= 1"),
  block_on(first_name, .where = "levenshtein(l.surname, r.surname) <= 2"),
  block_on(email),
  recall = 0.6
)

# Estimate u (splink: estimate_u_using_random_sampling) --------------------
model <- il_estimate_u(model, max_pairs = 5e5)

# EM training (splink: estimate_parameters_using_expectation_maximisation) -
model <- il_estimate_em(model, block_on(first_name, surname))
model <- il_estimate_em(model, block_on(dob))

# Visualizations (splink: match_weights_chart, m_u_parameters_chart) -------
autoplot(model)
il_weights(model)

# Training history (splink: parameter_estimate_comparisons_chart) ----------
il_training_history(model)

# Unlinkables analysis (splink: unlinkables_chart) -------------------------
il_unlinkables(model)

# Save model (splink: save_model_to_json) ----------------------------------
il_save(model, tempfile(fileext = ".json"), overwrite = TRUE)

dbDisconnect(con, shutdown = TRUE)
