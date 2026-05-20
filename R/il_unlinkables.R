#' Compute Unlinkable Records
#'
#' Calculates the proportion of records that cannot be linked at each
#' match-probability threshold. Returns a tidy tibble for plotting the
#' "unlinkables curve". This helps show how restrictive each threshold is.
#'
#' @param model A trained `il_model` object.
#'
#' @return A tibble with columns `threshold` and `pct_unlinkable`.
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
#'
#' il_unlinkables(model)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_unlinkables <- function(model) {
  validate_il_model(model)
  link_type <- model$link_type %||% 'dedupe'
  has_right_table <- !is.null(model$data$n_records_r) &&
    !identical(link_type, 'dedupe')
  n_records <- as.numeric(model$data$n_records_l)
  if (has_right_table) {
    n_records <- n_records + as.numeric(model$data$n_records_r)
  }
  thresholds <- seq(0, 1, by = 0.05)
  con <- model$con
  dialect <- detect_dialect(con)

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL path: score in-database, collect only max_prob per record
    lazy <- predict_lazy(model, threshold = 0)
    on.exit(drop_registered(con, lazy$predicted_tbl), add = TRUE)
    qpred <- sql_quote_identifier(lazy$predicted_tbl)

    if (has_right_table) {
      max_prob_sql <- glue::glue(
        'SELECT MAX(match_probability) AS max_prob FROM (',
        "SELECT 'l:' || CAST(unique_id_l AS VARCHAR) AS id, match_probability FROM {qpred} ",
        'UNION ALL ',
        "SELECT 'r:' || CAST(unique_id_r AS VARCHAR) AS id, match_probability FROM {qpred}",
        ') sub GROUP BY id'
      )
    } else {
      max_prob_sql <- glue::glue(
        'SELECT MAX(match_probability) AS max_prob FROM (',
        'SELECT CAST(unique_id_l AS VARCHAR) AS id, match_probability FROM {qpred} ',
        'UNION ALL ',
        'SELECT CAST(unique_id_r AS VARCHAR) AS id, match_probability FROM {qpred}',
        ') sub GROUP BY id'
      )
    }
    max_probs <- DBI::dbGetQuery(con, max_prob_sql)$max_prob

    pcts <- vapply(
      thresholds,
      function(t) {
        1 - sum(max_probs >= t) / n_records
      },
      numeric(1)
    )

    return(
      tibble::tibble(threshold = thresholds, pct_unlinkable = pcts) |>
        add_class('il_unlinkables')
    )
  }

  # R-side fallback for SQLite and other backends
  all_pairs <- predict(model, threshold = 0.0)

  results <- lapply(thresholds, function(t) {
    linked <- all_pairs[all_pairs$match_probability >= t, ]
    if (has_right_table) {
      linked_ids <- unique(c(
        paste0('l:', as.character(linked$unique_id_l)),
        paste0('r:', as.character(linked$unique_id_r))
      ))
    } else {
      linked_ids <- unique(c(
        as.character(linked$unique_id_l),
        as.character(linked$unique_id_r)
      ))
    }
    pct <- 1 - length(linked_ids) / n_records
    tibble::tibble(threshold = t, pct_unlinkable = pct)
  })

  do.call(rbind, results) |>
    add_class('il_unlinkables')
}
