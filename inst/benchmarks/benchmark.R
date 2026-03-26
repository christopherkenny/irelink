# irelink performance benchmark
# Runs the full pipeline on synthetic data and records wall-clock time
# for each stage.

devtools::load_all()

# --- Synthetic data -----------------------------------------------------------
set.seed(42)
make_fake_data <- function(n) {
  first_names <- c("John", "Jane", "Alice", "Bob", "Carol",
                    "David", "Eve", "Frank", "Grace", "Hank")
  surnames <- c("Smith", "Johnson", "Williams", "Brown", "Jones",
                "Garcia", "Miller", "Davis", "Wilson", "Moore")

  data.frame(
    unique_id = seq_len(n),
    first_name = sample(first_names, n, replace = TRUE),
    surname = sample(surnames, n, replace = TRUE),
    dob = as.character(
      as.Date("1960-01-01") + sample(0:20000, n, replace = TRUE)
    ),
    city = sample(c("Portland", "Seattle", "Denver", "Austin", "Boston"),
                  n, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

# --- Run benchmarks at several scales ----------------------------------------
run_benchmark <- function(n, label) {
  cat(sprintf("\n=== Benchmark: %s (n = %d) ===\n", label, n))
  df <- make_fake_data(n)
  timings <- list()

  # Spec
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_compare(city, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  # 1. Data upload / model creation
  timings$model_creation <- system.time({
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    model <- il_model(df, spec = spec, con = con)
  })["elapsed"]

  # 2. U estimation
  timings$u_estimation <- system.time({
    model <- il_estimate_u(model, max_pairs = min(n * (n - 1) / 2, 1e6))
  })["elapsed"]

  # 3. EM training
  timings$em_training <- system.time({
    model <- il_estimate_em(model, block_on(surname))
  })["elapsed"]

  # 4. Prediction
  timings$prediction <- system.time({
    pairs <- predict(model, threshold = 0.5)
  })["elapsed"]

  # 5. Clustering
  if (nrow(pairs) > 0) {
    timings$clustering <- system.time({
      clusters <- il_cluster(pairs)
    })["elapsed"]
  } else {
    timings$clustering <- 0
  }

  # Total
  timings$total <- sum(unlist(timings))

  DBI::dbDisconnect(con)

  cat(sprintf("  Model creation:  %6.3f s\n", timings$model_creation))
  cat(sprintf("  U estimation:    %6.3f s\n", timings$u_estimation))
  cat(sprintf("  EM training:     %6.3f s\n", timings$em_training))
  cat(sprintf("  Prediction:      %6.3f s\n", timings$prediction))
  cat(sprintf("  Clustering:      %6.3f s\n", timings$clustering))
  cat(sprintf("  TOTAL:           %6.3f s\n", timings$total))
  cat(sprintf("  Pairs predicted: %d\n", nrow(pairs)))

  invisible(timings)
}

results <- list()
for (n in c(200, 500, 1000, 2000)) {
  results[[as.character(n)]] <- run_benchmark(n, paste0("n=", n))
}

cat("\n\n=== Summary table ===\n")
cat(sprintf("%-8s %-12s %-12s %-12s %-12s %-12s %-12s\n",
            "N", "Model", "U-est", "EM", "Predict", "Cluster", "Total"))
for (nm in names(results)) {
  r <- results[[nm]]
  cat(sprintf("%-8s %10.3f s %10.3f s %10.3f s %10.3f s %10.3f s %10.3f s\n",
              nm, r$model_creation, r$u_estimation, r$em_training,
              r$prediction, r$clustering, r$total))
}
