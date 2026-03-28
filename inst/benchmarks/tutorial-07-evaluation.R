# Tutorial 07 — Evaluation
# Translation of splink docs/demos/tutorials/07_Evaluation.ipynb
# -----------------------------------------------------------------------
# Covers: error analysis, accuracy metrics, precision/recall,
#         ROC curves, threshold selection, unlinkables
#
# NOTE: splink's fake_1000 includes a ground-truth 'cluster' column and
# a separate labels dataset (splink_dataset_labels.fake_1000_labels).
# irelink's il_demo("fake_1000") does not include ground-truth labels,
# so this tutorial demonstrates evaluation with manually created labels.

library(irelink)
library(duckdb)
library(DBI)
library(ggplot2)

df <- il_demo("fake_1000")
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
cat("predictions:", nrow(predictions), "\n")

# Create synthetic labels for demonstration
# In practice, these come from manual review or known entity IDs
# (splink: splink_dataset_labels.fake_1000_labels)
if (nrow(predictions) > 0) {
  n_labels <- min(nrow(predictions), 30)
  labels <- predictions[seq_len(n_labels), c("unique_id_l", "unique_id_r")]
  # Mark high-probability pairs as matches, low-probability as non-matches
  labels$is_match <- as.integer(
    predictions$match_probability[seq_len(n_labels)] > 0.5
  )

  # Error analysis (splink: prediction_errors_from_labels_table) -----------
  errors <- il_errors(model, labels = labels, threshold = 0.85)
  cat("errors:", nrow(errors), "\n")

  # Accuracy table (splink: accuracy_analysis, output_type="table") --------
  accuracy <- il_accuracy(model, labels = labels)
  cat("accuracy thresholds:", nrow(accuracy), "\n")

  # Precision-recall (splink: accuracy_analysis, threshold_selection) ------
  pr <- il_precision_recall(model, labels = labels)
  cat("precision_recall:", nrow(pr), "\n")

  # ROC curve (splink: accuracy_analysis, output_type="roc") ---------------
  roc <- il_roc(model, labels = labels)
  cat("roc points:", nrow(roc), "\n")
}

# Unlinkables (splink: unlinkables_chart) -----------------------------------
unlink_tbl <- il_unlinkables(model)
cat("unlinkables:", nrow(unlink_tbl), "\n")

dbDisconnect(con, shutdown = TRUE)
