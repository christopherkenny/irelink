devtools::load_all()
set.seed(42)

# --- Profile il_find_matches row-by-row loop ---
cat("=== il_find_matches profiling ===\n")
first_names <- c("John", "Jane", "Alice", "Bob", "Carol",
                 "David", "Eve", "Frank", "Grace", "Hank")
surnames <- c("Smith", "Johnson", "Williams", "Brown", "Jones",
              "Garcia", "Miller", "Davis", "Wilson", "Moore")
n <- 500
df <- data.frame(
  unique_id = seq_len(n),
  first_name = sample(first_names, n, replace = TRUE),
  surname = sample(surnames, n, replace = TRUE),
  dob = as.character(as.Date("1960-01-01") + sample(0:20000, n, replace = TRUE)),
  city = sample(c("Portland","Seattle","Denver","Austin","Boston"), n, replace = TRUE),
  stringsAsFactors = FALSE
)
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_compare(city, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
model <- il_model(df, spec = spec, con = con) |>
  il_estimate_u() |>
  il_estimate_em(block_on(surname))

new_recs <- data.frame(
  first_name = sample(first_names, 5, replace = TRUE),
  surname = sample(surnames, 5, replace = TRUE),
  dob = as.character(as.Date("1980-01-01") + sample(0:5000, 5, replace = TRUE)),
  city = sample(c("Portland","Seattle"), 5, replace = TRUE),
  stringsAsFactors = FALSE
)
cat("  5 new records against 500:\n")
t1 <- system.time(res <- il_find_matches(model, new_recs))["elapsed"]
cat(sprintf("    %.3f s  (%d matches)\n", t1, nrow(res)))
flush.console()

new_recs_50 <- data.frame(
  first_name = sample(first_names, 50, replace = TRUE),
  surname = sample(surnames, 50, replace = TRUE),
  dob = as.character(as.Date("1980-01-01") + sample(0:5000, 50, replace = TRUE)),
  city = sample(c("Portland","Seattle"), 50, replace = TRUE),
  stringsAsFactors = FALSE
)
cat("  50 new records against 500:\n")
t2 <- system.time(res2 <- il_find_matches(model, new_recs_50))["elapsed"]
cat(sprintf("    %.3f s  (%d matches)\n", t2, nrow(res2)))
DBI::dbDisconnect(con)
flush.console()

# --- igraph comparison for clustering ---
cat("\n=== igraph vs union-find clustering ===\n")
if (requireNamespace("igraph", quietly = TRUE)) {
  for (n_edges in c(5000, 20000, 50000, 100000)) {
    n_nodes <- n_edges / 5
    ids_l <- as.character(sample(seq_len(n_nodes), n_edges, replace = TRUE))
    ids_r <- as.character(sample(seq_len(n_nodes), n_edges, replace = TRUE))
    probs <- runif(n_edges, 0.5, 1)
    pairs_t <- tibble::tibble(
      unique_id_l = ids_l, unique_id_r = ids_r,
      match_weight = rnorm(n_edges), match_probability = probs
    )
    pairs_t <- structure(pairs_t, class = c("il_compared", class(pairs_t)), model = NULL)

    # Union-find (current)
    t_uf <- system.time(cl_uf <- il_cluster(pairs_t))["elapsed"]

    # igraph components
    t_ig <- system.time({
      all_ids <- unique(c(ids_l, ids_r))
      g <- igraph::graph_from_data_frame(
        data.frame(from = ids_l, to = ids_r, stringsAsFactors = FALSE),
        directed = FALSE, vertices = data.frame(name = all_ids)
      )
      comp <- igraph::components(g)
      result_ig <- tibble::tibble(
        unique_id = all_ids,
        cluster_id = paste0("cluster_", comp$membership[all_ids])
      )
    })["elapsed"]

    cat(sprintf("  %6d edges: union-find %.3f s  |  igraph %.3f s  |  speedup %.1fx\n",
                n_edges, t_uf, t_ig, t_uf / max(t_ig, 0.001)))
    flush.console()
  }
} else {
  cat("  igraph not available\n")
}

# --- Matrix multiply vs loop for scoring ---
cat("\n=== Matrix vs loop scoring ===\n")
n_pairs <- 100000
n_comp <- 4
gm <- matrix(sample(0:1, n_pairs * n_comp, replace = TRUE), nrow = n_pairs)
m_match <- runif(n_comp, 0.7, 0.99)
u_match <- runif(n_comp, 0.01, 0.3)
m_nm <- 1 - m_match
u_nm <- 1 - u_match

# Loop approach (current)
t_loop <- system.time({
  mw_loop <- numeric(n_pairs)
  for (j in seq_len(n_comp)) {
    g <- gm[, j]
    w <- ifelse(g == 1L,
      log2(pmax(m_match[j], 1e-10) / pmax(u_match[j], 1e-10)),
      log2(pmax(m_nm[j], 1e-10) / pmax(u_nm[j], 1e-10))
    )
    mw_loop <- mw_loop + w
  }
})["elapsed"]

# Matrix approach
t_mat <- system.time({
  w1 <- log2(pmax(m_match, 1e-10) / pmax(u_match, 1e-10))
  w0 <- log2(pmax(m_nm, 1e-10) / pmax(u_nm, 1e-10))
  mw_mat <- as.numeric(gm %*% w1 + (1 - gm) %*% w0)
})["elapsed"]

cat(sprintf("  100K pairs, 4 comps: loop %.3f s  |  matrix %.3f s  |  max diff: %e\n",
            t_loop, t_mat, max(abs(mw_loop - mw_mat))))

# Larger
n_pairs2 <- 500000
gm2 <- matrix(sample(0:1, n_pairs2 * n_comp, replace = TRUE), nrow = n_pairs2)
t_loop2 <- system.time({
  mw2 <- numeric(n_pairs2)
  for (j in seq_len(n_comp)) {
    g <- gm2[, j]
    w <- ifelse(g == 1L,
      log2(pmax(m_match[j], 1e-10) / pmax(u_match[j], 1e-10)),
      log2(pmax(m_nm[j], 1e-10) / pmax(u_nm[j], 1e-10))
    )
    mw2 <- mw2 + w
  }
})["elapsed"]
t_mat2 <- system.time({
  w1 <- log2(pmax(m_match, 1e-10) / pmax(u_match, 1e-10))
  w0 <- log2(pmax(m_nm, 1e-10) / pmax(u_nm, 1e-10))
  mw2_m <- as.numeric(gm2 %*% w1 + (1 - gm2) %*% w0)
})["elapsed"]
cat(sprintf("  500K pairs, 4 comps: loop %.3f s  |  matrix %.3f s\n", t_loop2, t_mat2))

cat("\nDone.\n")
