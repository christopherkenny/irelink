#' Estimate Non-Match (u) Parameters
#'
#' Estimates the u probabilities (the probability of observing each
#' comparison level given that the records do **not** match) by randomly
#' sampling record pairs. Most random pairs are non-matches, so the
#' observed level frequencies approximate the u distribution.
#'
#' @param model An `il_model` object (piped in).
#' @param max_pairs Maximum number of random pairs to sample. Defaults to
#'   `1e6`.
#'
#' @return An updated `il_model` with estimated u parameters.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c("John", "Jon", "Jane", "Jane", "Bob",
#'                   "Bobby", "Alice", "Alicia", "Tom", "Thomas",
#'                   "John", "Jon", "Jane", "Janet", "Bob",
#'                   "Robert", "Alice", "Alison", "Tom", "Tomas"),
#'   surname = c("Smith", "Smith", "Doe", "Doe", "Jones",
#'               "Jones", "Brown", "Brown", "White", "White",
#'               "Smith", "Smyth", "Doe", "Doe", "Jones",
#'               "Jones", "Brown", "Browne", "White", "White"),
#'   dob = c("1990-01-01", "1990-01-01", "1985-06-15", "1985-06-15",
#'           "2000-12-01", "2000-12-01", "1975-03-22", "1975-03-22",
#'           "1988-07-04", "1988-07-04", "1990-01-01", "1990-01-02",
#'           "1985-06-15", "1985-06-16", "2000-12-01", "2000-12-02",
#'           "1975-03-22", "1975-03-23", "1988-07-04", "1988-07-05"),
#'   city = c("London", "London", "Paris", "Paris", "Berlin",
#'            "Berlin", "Rome", "Rome", "Madrid", "Madrid",
#'            "London", "London", "Paris", "Paris", "Berlin",
#'            "Berlin", "Rome", "Rome", "Madrid", "Madrid"),
#'   email = c("john@example.com", "jon@example.com", "jane@example.com",
#'             "jane@example.com", "bob@example.com", "bobby@example.com",
#'             "alice@example.com", "alicia@example.com", "tom@example.com",
#'             "thomas@example.com", "john@example.com", "jon@example.com",
#'             "jane@example.com", "janet@example.com", "bob@example.com",
#'             "robert@example.com", "alice@example.com", "alison@example.com",
#'             "tom@example.com", "tomas@example.com")
#' )
#' con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' model <- il_model(df, spec = spec, con = con)
#'
#' model <- il_estimate_u(model)
#' DBI::dbDisconnect(con)
il_estimate_u <- function(model, max_pairs = 1e6) {
  validate_il_model(model)
  pairs <- get_all_pairs(model, max_pairs = max_pairs)
  comparisons <- model$spec$comparisons

  if (nrow(pairs) == 0L) {
    cli::cli_abort("No pairs available for u estimation.")
  }

  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  # u = fraction of random pairs that agree at each level
  n_pairs <- nrow(pairs)
  u_match <- colMeans(gamma_mat)
  u_nonmatch <- 1 - u_match

  comp_names <- colnames(gamma_mat)
  params_tbl <- tibble::tibble(
    comparison = rep(comp_names, each = 2L),
    level = rep(c("match", "non_match"), times = length(comp_names)),
    u = as.numeric(rbind(u_match, u_nonmatch))
  )

  if (is.null(model$params$comparisons)) {
    params_tbl$m <- NA_real_
  } else {
    params_tbl <- merge(
      params_tbl[, c("comparison", "level", "u")],
      model$params$comparisons[, c("comparison", "level", "m")],
      by = c("comparison", "level"), all.x = TRUE
    )
    params_tbl <- tibble::as_tibble(params_tbl)
  }

  model$params$comparisons <- params_tbl
  model
}
