# irelink performance benchmark
# Runs the full pipeline on synthetic data and records wall-clock time
# for each stage.

devtools::load_all()
set.seed(42)

make_fake_data <- function(n) {
  first_names <- c(
    "John",
    "Jane",
    "Alice",
    "Bob",
    "Carol",
    "David",
    "Eve",
    "Frank",
    "Grace",
    "Hank"
  )
  surnames <- c(
    "Smith",
    "Johnson",
    "Williams",
    "Brown",
    "Jones",
    "Garcia",
    "Miller",
    "Davis",
    "Wilson",
    "Moore"
  )

  data.frame(
    unique_id = seq_len(n),
    first_name = sample(first_names, n, replace = TRUE),
    surname = sample(surnames, n, replace = TRUE),
    dob = as.character(
      as.Date("1960-01-01") + sample(0:20000, n, replace = TRUE)
    ),
    city = sample(
      c("Portland", "Seattle", "Denver", "Austin", "Boston"),
      n,
      replace = TRUE
    ),
    stringsAsFactors = FALSE
  )
}

run_benchmark <- function(n) {
  df <- make_fake_data(n)
  spec <- il_spec() |>
    il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
    il_compare(dob, cl_exact()) |>
    il_compare(city, cl_exact()) |>
    il_block_on(surname) |>
    il_block_on(first_name)

  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit({
    il_cleanup_all(con)
    DBI::dbDisconnect(con)
  })

  t_model <- system.time(model <- il_model(df, spec = spec, con = con))[
    "elapsed"
  ]
  t_u <- system.time(
    model <- il_estimate_u(
      model,
      max_pairs = min(n * (n - 1) / 2, 1e6),
      chunk_size = 250000
    )
  )["elapsed"]
  t_em <- system.time(model <- il_estimate_em(model, block_on(surname)))[
    "elapsed"
  ]
  t_predict <- system.time(pairs <- predict(model, threshold = 0.5))["elapsed"]
  t_cluster <- 0
  if (nrow(pairs) > 0) {
    t_cluster <- system.time(il_cluster(pairs))["elapsed"]
  }

  tibble::tibble(
    n = n,
    model = t_model,
    u_est = t_u,
    em = t_em,
    predict = t_predict,
    cluster = t_cluster,
    total = t_model + t_u + t_em + t_predict + t_cluster
  )
}

lapply(c(200, 500, 1000, 2000), run_benchmark) |> dplyr::bind_rows()
