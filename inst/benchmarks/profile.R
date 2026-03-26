# Profile breakdown of individual stages
devtools::load_all()
set.seed(42)
first_names <- c("John", "Jane", "Alice", "Bob", "Carol",
                 "David", "Eve", "Frank", "Grace", "Hank")
surnames <- c("Smith", "Johnson", "Williams", "Brown", "Jones",
              "Garcia", "Miller", "Davis", "Wilson", "Moore")
n <- 1000
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
model <- il_model(df, spec = spec, con = con)

cat("--- U estimation breakdown (n=1000) ---\n")
t1 <- system.time(pairs_u <- irelink:::get_all_pairs(model, max_pairs = 1e6))["elapsed"]
cat(sprintf("  get_all_pairs:       %.3f s  (%d pairs)\n", t1, nrow(pairs_u)))

t2 <- system.time(gm <- irelink:::compute_gamma_matrix(pairs_u, spec$comparisons))["elapsed"]
cat(sprintf("  compute_gamma_matrix: %.3f s\n", t2))

# Per-method gamma
cat("\n--- compute_gamma per method (on u-est pairs) ---\n")
for (j in seq_along(spec$comparisons)) {
  comp <- spec$comparisons[[j]]
  col <- comp$columns
  val_l <- pairs_u[[paste0("l_", col)]]
  val_r <- pairs_u[[paste0("r_", col)]]
  t <- system.time(irelink:::compute_gamma(val_l, val_r, comp$method))["elapsed"]
  cat(sprintf("  %-20s (%s): %.3f s on %d pairs\n", col, comp$method$method, t, length(val_l)))
}

# Profile EM
model <- il_estimate_u(model)
br <- block_on(surname)
cat("\n--- EM breakdown ---\n")
t4 <- system.time(pairs_em <- irelink:::get_blocked_pairs(model, br))["elapsed"]
cat(sprintf("  get_blocked_pairs:   %.3f s  (%d pairs)\n", t4, nrow(pairs_em)))

t5 <- system.time(gm_em <- irelink:::compute_gamma_matrix(pairs_em, spec$comparisons))["elapsed"]
cat(sprintf("  compute_gamma_matrix: %.3f s\n", t5))

# Profile scoring
params <- model$params$comparisons
comp_names <- vapply(spec$comparisons, function(c) c$columns, character(1))

t6 <- system.time(mu <- irelink:::extract_mu_vectors(params, comp_names))["elapsed"]
cat(sprintf("  extract_mu_vectors:  %.3f s\n", t6))

t7 <- system.time(mw <- irelink:::score_gamma_matrix(gm_em, mu))["elapsed"]
cat(sprintf("  score_gamma_matrix:  %.3f s\n", t7))

t8 <- system.time(mp <- irelink:::weight_to_probability(mw, 0.05))["elapsed"]
cat(sprintf("  weight_to_probability: %.3f s\n", t8))

# Profile EM E-step vectorized vs loop
n_pairs <- nrow(pairs_em)
n_comp <- ncol(gm_em)
m_match <- rep(0.9, n_comp)
m_nonmatch <- rep(0.1, n_comp)
u_match <- colMeans(gm_em)
u_nonmatch <- 1 - u_match
prior <- 0.05

cat("\n--- EM single iteration (E-step + M-step) ---\n")
t9 <- system.time({
  log_match <- rep(log(prior), n_pairs)
  log_nonmatch <- rep(log(1 - prior), n_pairs)
  for (jj in seq_len(n_comp)) {
    g <- gm_em[, jj]
    lm_1 <- log(pmax(m_match[jj], 1e-10))
    lm_0 <- log(pmax(m_nonmatch[jj], 1e-10))
    lu_1 <- log(pmax(u_match[jj], 1e-10))
    lu_0 <- log(pmax(u_nonmatch[jj], 1e-10))
    log_match <- log_match + ifelse(g == 1L, lm_1, lm_0)
    log_nonmatch <- log_nonmatch + ifelse(g == 1L, lu_1, lu_0)
  }
  max_log <- pmax(log_match, log_nonmatch)
  weights <- exp(log_match - max_log) / (exp(log_match - max_log) + exp(log_nonmatch - max_log))
})["elapsed"]
cat(sprintf("  E-step:              %.3f s\n", t9))

t10 <- system.time({
  sum_w <- sum(weights)
  for (jj in seq_len(n_comp)) {
    g <- gm_em[, jj]
    raw <- (sum(weights * g) + 0.5) / (sum_w + 1.0)
    m_match[jj] <- max(min(raw, 0.99), 0.01)
    m_nonmatch[jj] <- 1 - m_match[jj]
  }
})["elapsed"]
cat(sprintf("  M-step:              %.3f s\n", t10))

# Profile pair deduplication
cat("\n--- Pair deduplication ---\n")
all_pairs <- list()
for (br2 in spec$blocking_rules) {
  bp <- irelink:::get_blocked_pairs(model, br2)
  if (nrow(bp) > 0L) all_pairs <- c(all_pairs, list(bp))
}
pairs_all <- do.call(rbind, all_pairs)
t11 <- system.time({
  pair_key <- paste(pairs_all$l_unique_id, pairs_all$r_unique_id, sep = "||")
  pairs_dedup <- pairs_all[!duplicated(pair_key), , drop = FALSE]
})["elapsed"]
cat(sprintf("  paste + dedup:       %.3f s  (%d -> %d pairs)\n",
            t11, nrow(pairs_all), nrow(pairs_dedup)))

DBI::dbDisconnect(con)
cat("\nDone.\n")
