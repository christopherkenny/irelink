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
#' @return A tibble with columns `step`, `order`, `contribution`,
#'   `direction`, `start`, and `end`. The rows include the prior odds,
#'   one row per comparison contribution, and a final total.
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
  pairs <- ensure_collected(pairs)
  validate_il_compared(pairs)
  if (
    !is.numeric(which) ||
      length(which) != 1L ||
      is.na(which) ||
      !is.finite(which) ||
      which < 1 ||
      which != as.integer(which)
  ) {
    cli::cli_abort('{.arg which} must be a positive row index.')
  }
  which <- as.integer(which)
  if (which > nrow(pairs)) {
    cli::cli_abort('{.arg which} must identify a row present in {.arg pairs}.')
  }
  model <- attr(pairs, 'model')
  if (is.null(model)) {
    cli::cli_abort('No model attached to the {.cls il_compared} object.')
  }

  row <- pairs[which, ]
  if (identical(model$params$estimator_mode, 'dependency-aware')) {
    cli::cli_abort(
      '{.fn il_waterfall} decomposes fieldwise independent weights and is not supported for dependency-aware scores.'
    )
  }
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  comp_names <- comparison_names(comparisons)

  mu <- extract_mu_vectors(params, comp_names)
  gamma <- vapply(
    comp_names,
    function(cn) {
      as.integer(row[[paste0('gamma_', cn)]])
    },
    integer(1)
  )

  # Collect per-comparison TF adjustments from stored columns
  tf_adjs <- vapply(
    comp_names,
    function(cn) {
      col_name <- paste0('tf_adj_', cn)
      val <- 0
      if (col_name %in% names(row)) {
        val <- as.numeric(row[[col_name]])
      }
      if (is.na(val)) 0 else val
    },
    numeric(1)
  )

  has_tf <- any(tf_adjs != 0)
  contributions <- per_comparison_contribution(
    gamma,
    mu,
    comp_names,
    if (has_tf) tf_adjs else NULL
  )
  prior <- safe_prior(model)
  prior_weight <- log2(prior / (1 - prior))
  final_weight <- prior_weight + sum(contributions)

  direction <- c(
    'prior',
    ifelse(contributions >= 0, 'positive', 'negative'),
    'final'
  )
  step <- c('Prior', comp_names, 'Final')
  contribution <- c(prior_weight, contributions, final_weight)
  cumulative <- cumsum(c(prior_weight, contributions))
  start <- c(0, utils::head(cumulative, -1), 0)
  end <- c(cumulative, final_weight)

  tibble::tibble(
    step = step,
    order = seq_along(step),
    contribution = contribution,
    direction = direction,
    start = start,
    end = end
  )
}
