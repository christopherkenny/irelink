#' Estimate the Prior Match Probability
#'
#' Estimates the probability that two randomly selected records from the
#' dataset are a match, using deterministic rules and a recall assumption.
#' This prior anchors the Fellegi-Sunter model. Analogous to fitting a
#' base rate before more detailed parameter estimation.
#'
#' @param model An `il_model` object (piped in).
#' @param ... Blocking rules created by [block_on()] that define
#'   deterministic matching criteria.
#' @param recall A numeric value between 0 and 1 representing the assumed
#'   recall of the deterministic rules. Defaults to `0.7`.
#'
#' @return An updated `il_model` with the estimated prior.
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
#' model <- il_estimate_prior(model, block_on(first_name, surname, dob))
#' DBI::dbDisconnect(con)
il_estimate_prior <- function(model, ..., recall = 0.7) {
  validate_il_model(model)
  rules <- list(...)

  if (length(rules) == 0L) {
    cli::cli_abort("{.fn il_estimate_prior} requires at least one blocking rule.")
  }

  con <- model$con
  tbl <- model$data$tbl_l
  n_total <- model$data$n_records_l

  if (model$link_type == "dedupe") {
    total_pairs <- n_total * (n_total - 1L) / 2L
  } else {
    n_r <- model$data$n_records_r %||% n_total
    total_pairs <- n_total * n_r
  }

  # Count pairs produced by each blocking rule
  n_blocked <- 0L
  for (rule in rules) {
    if (!inherits(rule, "il_blocking_rule")) next
    tbl_r <- if (model$link_type == "dedupe") tbl else (model$data$tbl_r %||% tbl)
    where <- build_blocking_condition(rule$columns)
    n_blocked <- n_blocked + count_blocked_pairs(
      con, tbl, tbl_r, where, dedupe = (model$link_type == "dedupe")
    )
  }

  estimated_matches <- n_blocked / recall
  prior <- min(max(estimated_matches / total_pairs, 1e-6), 1 - 1e-6)

  model$params$prior <- prior
  model
}
