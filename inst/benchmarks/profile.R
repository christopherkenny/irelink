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
on.exit({
  il_cleanup_all(con)
  DBI::dbDisconnect(con)
})
model <- il_model(df, spec = spec, con = con)

# U estimation breakdown
t1 <- system.time(pairs_u <- get_all_pairs(model, max_pairs = 1e6))["elapsed"]
t2 <- system.time(gm <- compute_gamma_matrix(pairs_u, spec$comparisons))["elapsed"]

# compute_gamma per method (on u-est pairs)
gamma_times <- lapply(seq_along(spec$comparisons), \(j) {
  comp <- spec$comparisons[[j]]
  val_l <- pairs_u[[paste0("l_", comp$columns)]]
  val_r <- pairs_u[[paste0("r_", comp$columns)]]
  t <- system.time(compute_gamma(val_l, val_r, comp$method))["elapsed"]
  tibble::tibble(column = comp$columns, method = comp$method$method, elapsed = t, n_pairs = length(val_l))
}) |> dplyr::bind_rows()

# EM breakdown
model <- il_estimate_u(model, profile_sql = TRUE)
t4 <- system.time(pairs_em <- get_blocked_pairs(model, block_on(surname)))["elapsed"]
t5 <- system.time(gm_em <- compute_gamma_matrix(pairs_em, spec$comparisons))["elapsed"]

# Profile scoring
comp_names <- vapply(spec$comparisons, \(c) c$columns, character(1))
t6 <- system.time(mu <- extract_mu_vectors(model$params$comparisons, comp_names))["elapsed"]
t7 <- system.time(mw <- score_gamma_matrix(gm_em, mu))["elapsed"]
t8 <- system.time(weight_to_probability(mw, 0.05))["elapsed"]

# EM single iteration (E-step + M-step)
n_pairs <- nrow(pairs_em)
n_comp <- ncol(gm_em)
m_match <- rep(0.9, n_comp)
m_nonmatch <- rep(0.1, n_comp)
u_match <- colMeans(gm_em)
u_nonmatch <- 1 - u_match
prior <- 0.05

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

t10 <- system.time({
  sum_w <- sum(weights)
  for (jj in seq_len(n_comp)) {
    g <- gm_em[, jj]
    raw <- (sum(weights * g) + 0.5) / (sum_w + 1.0)
    m_match[jj] <- max(min(raw, 0.99), 0.01)
    m_nonmatch[jj] <- 1 - m_match[jj]
  }
})["elapsed"]

# Pair deduplication
all_pairs <- lapply(spec$blocking_rules, \(br) get_blocked_pairs(model, br)) |>
  dplyr::bind_rows()
t11 <- system.time({
  pair_key <- paste(all_pairs$l_unique_id, all_pairs$r_unique_id, sep = "||")
  pairs_dedup <- all_pairs[!duplicated(pair_key), , drop = FALSE]
})["elapsed"]

tibble::tibble(
  stage = c(
    "get_all_pairs", "compute_gamma_matrix (u)",
    "get_blocked_pairs", "compute_gamma_matrix (em)",
    "extract_mu_vectors", "score_gamma_matrix", "weight_to_probability",
    "E-step", "M-step", "pair dedup"
  ),
  elapsed = c(t1, t2, t4, t5, t6, t7, t8, t9, t10, t11)
)
gamma_times
