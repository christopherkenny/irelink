#' Extract Waterfall Data for a Single Pair
#'
#' Returns a tidy tibble showing how each comparison contributed to the
#' total match weight for a specific record pair. Designed for use with
#' [ggplot2::geom_col()] and [ggplot2::coord_flip()].
#'
#' @param pairs An `il_compared` tibble from [predict.il_model()].
#' @param which An integer index identifying which row (pair) to
#'   decompose. Defaults to `1L`.
#'
#' @return A tibble with columns `step`, `order`, `contribution`, and
#'   `direction` (positive, negative, prior, or final).
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
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#' pairs <- predict(model, threshold = 0.5)
#'
#' il_waterfall(pairs, which = 1)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_waterfall <- function(pairs, which = 1L) {
  validate_il_compared(pairs)
  model <- attr(pairs, 'model')
  if (is.null(model)) {
    cli::cli_abort('No model attached to the {.cls il_compared} object.')
  }

  row <- pairs[which, ]
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))

  mu <- extract_mu_vectors(params, comp_names)
  gamma <- vapply(comp_names, function(cn) {
    as.integer(row[[paste0('gamma_', cn)]])
  }, integer(1))

  # Collect per-comparison TF adjustments from stored columns
  tf_adjs <- vapply(comp_names, function(cn) {
    col_name <- paste0('tf_adj_', cn)
    if (col_name %in% names(row)) as.numeric(row[[col_name]]) else 0
  }, numeric(1))

  has_tf <- any(tf_adjs != 0)
  contributions <- per_comparison_contribution(
    gamma, mu, if (has_tf) tf_adjs else NULL
  )

  direction <- ifelse(contributions >= 0, 'positive', 'negative')

  tibble::tibble(
    step = comp_names,
    order = seq_along(comp_names),
    contribution = contributions,
    direction = direction
  )
}
