#' Estimate the Prior Match Probability
#'
#' Estimates the probability that two randomly selected records from the
#' dataset are a match, using deterministic rules and a recall assumption.
#' This prior anchors the Fellegi-Sunter model before more detailed
#' parameter estimation.
#'
#' @param model An `il_model` object (piped in).
#' @param ... Blocking rules created by [block_on()] that define
#'   deterministic matching criteria.
#' @param recall A numeric value between 0 and 1 representing the assumed
#'   recall of the deterministic rules. Defaults to `0.7`.
#' @param profile_sql Logical. If `TRUE`, store lightweight SQL timing metadata
#'   in `model$params$sql_profile`.
#'
#' @return An updated `il_model` with the estimated prior.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = 1:20,
#'   first_name = c(
#'     'John', 'Jon', 'Jane', 'Jane', 'Bob',
#'     'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
#'     'John', 'Jon', 'Jane', 'Janet', 'Bob',
#'     'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
#'   ),
#'   surname = c(
#'     'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Brown', 'White', 'White',
#'     'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
#'     'Jones', 'Brown', 'Browne', 'White', 'White'
#'   ),
#'   dob = c(
#'     '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
#'     '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
#'     '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
#'     '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
#'     '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
#'   ),
#'   city = c(
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
#'     'London', 'London', 'Paris', 'Paris', 'Berlin',
#'     'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
#'   ),
#'   email = c(
#'     'john@example.com', 'jon@example.com', 'jane@example.com',
#'     'jane@example.com', 'bob@example.com', 'bobby@example.com',
#'     'alice@example.com', 'alicia@example.com', 'tom@example.com',
#'     'thomas@example.com', 'john@example.com', 'jon@example.com',
#'     'jane@example.com', 'janet@example.com', 'bob@example.com',
#'     'robert@example.com', 'alice@example.com', 'alison@example.com',
#'     'tom@example.com', 'tomas@example.com'
#'   )
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_exact()) |>
#'   il_block_on(surname) |>
#'   il_block_on(first_name)
#' model <- il_model(df, spec = spec, con = con)
#'
#' model <- il_estimate_prior(model, block_on(first_name, surname, dob))
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_estimate_prior <- function(model, ..., recall = 0.7, profile_sql = FALSE) {
  validate_il_model(model)
  profile <- il_new_sql_profile(profile_sql)
  rules <- list(...)

  if (length(rules) == 0L) {
    cli::cli_abort('{.fn il_estimate_prior} requires at least one blocking rule.')
  }
  if (!is.numeric(recall) || length(recall) != 1L || !is.finite(recall) ||
    recall <= 0 || recall > 1) {
    cli::cli_abort('{.arg recall} must be a finite number with 0 < recall <= 1.')
  }
  invalid_rules <- !vapply(rules, inherits, logical(1), 'il_blocking_rule')
  if (any(invalid_rules)) {
    cli::cli_abort(
      '{.fn il_estimate_prior} only accepts blocking rules created by {.fn block_on}.'
    )
  }

  con <- model$con
  tbl <- model$data$tbl_l
  tbl_r <- model$data$tbl_r %||% tbl
  n_total <- as.numeric(model$data$n_records_l)

  if (model$link_type == 'dedupe') {
    total_pairs <- n_total * (n_total - 1) / 2
  } else if (model$link_type == 'link_and_dedupe') {
    n_r <- as.numeric(model$data$n_records_r %||% n_total)
    total_pairs <- (n_total * n_r) +
      (n_total * (n_total - 1) / 2) +
      (n_r * (n_r - 1) / 2)
  } else {
    n_r <- as.numeric(model$data$n_records_r %||% n_total)
    total_pairs <- n_total * n_r
  }

  n_blocked <- count_unique_blocked_pairs(
    con = con,
    tbl_l = tbl,
    tbl_r = tbl_r,
    rules = rules,
    link_type = model$link_type %||% 'dedupe',
    dialect = detect_dialect(con),
    profile = profile
  )

  estimated_matches <- n_blocked / recall
  prior <- min(max(estimated_matches / total_pairs, 1e-6), 1 - 1e-6)

  model$params$prior <- prior
  if (isTRUE(profile_sql)) {
    model$params$sql_profile <- il_sql_profile_entries(profile)
  }
  model
}
