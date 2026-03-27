#' Extract Match Weights by Comparison Level
#'
#' Returns a tidy tibble of comparison levels with their m probabilities,
#' u probabilities, and log-2 Bayes factors (match weights). Designed for
#' use with [ggplot2::geom_col()] and [ggplot2::facet_wrap()].
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `comparison`, `level`, `m_prob`,
#'   `u_prob`, and `log2_bayes_factor`.
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
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#'
#' il_weights(model)
#' DBI::dbDisconnect(con)
il_weights <- function(model) {
  validate_il_model(model)
  params <- model$params$comparisons
  if (is.null(params)) {
    cli::cli_abort("Model has no parameters yet. Run training verbs first.")
  }
  m <- params$m
  u <- params$u
  # Guard against log(0) or division by zero
  m <- pmax(m, 1e-10)
  u <- pmax(u, 1e-10)
  match_weight <- log2(m / u)

  tibble::tibble(
    comparison = params$comparison,
    level = params$level,
    m_prob = params$m,
    u_prob = params$u,
    weight = match_weight
  )
}
