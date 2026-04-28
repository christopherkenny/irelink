# Tutorial 07 — Evaluation
# Translation of splink docs/demos/tutorials/07_Evaluation.ipynb
# Covers: error analysis, accuracy metrics, precision/recall,
#         ROC curves, threshold selection, unlinkables
#
# NOTE: splink's fake_1000 includes a ground-truth 'cluster' column and
# a separate labels dataset (fake_1000_labels).
# irelink bundles both as lazy-loaded datasets.

library(irelink)
library(duckdb)
library(DBI)
library(ggplot2)

df <- fake_1000
con <- dbConnect(duckdb())

# Build model with broad blocking for evaluation recall
spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_levenshtein(1)) |>
  il_compare(city, cl_exact(term_frequency = TRUE)) |>
  il_compare(email, cl_email()) |>
  il_block_on(first_name) |>
  il_block_on(surname) |>
  il_block_on(dob)

model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model, max_pairs = 5e5)
model <- il_estimate_em(model, block_on(first_name, surname))
model <- il_estimate_em(model, block_on(dob))

# Generate predictions at a low threshold for evaluation
predictions <- predict(model, threshold = 0.01)

# Create synthetic labels for demonstration
# In practice, these come from manual review or known entity IDs
if (nrow(predictions) > 0) {
  n_labels <- min(nrow(predictions), 30)
  labels <- predictions[seq_len(n_labels), c("unique_id_l", "unique_id_r")]
  # Mark high-probability pairs as matches, low-probability as non-matches
  labels$is_match <- as.integer(
    predictions$match_probability[seq_len(n_labels)] > 0.5
  )

  # Error analysis (splink: prediction_errors_from_labels_table)
  il_errors(model, labels = labels, threshold = 0.85)

  # Accuracy table (splink: accuracy_analysis, output_type="table")
  il_accuracy(model, labels = labels)

  # Precision-recall (splink: accuracy_analysis, threshold_selection)
  il_precision_recall(model, labels = labels)

  # ROC curve (splink: accuracy_analysis, output_type="roc")
  il_roc(model, labels = labels)
}

# Unlinkables (splink: unlinkables_chart)
il_unlinkables(model)

il_cleanup(model)
il_cleanup_all(con)
dbDisconnect(con, shutdown = TRUE)
