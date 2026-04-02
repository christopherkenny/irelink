#' Find Matches for New Records
#'
#' Scores new records against the data already loaded into a trained
#' model. Useful for real-time or incremental matching where new records
#' arrive after the model has been trained.
#'
#' @param model A trained `il_model` object.
#' @param new_records A data frame, dbplyr `tbl_lazy`, or character table
#'   name of new records to match against the model's existing data.
#' @param threshold A numeric value between 0 and 1. Only matches at or
#'   above this probability are returned. Defaults to `0.85`.
#'
#' @return An `il_compared` tibble of scored pairs between new records
#'   and existing data.
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
#' new_df <- data.frame(
#'   first_name = 'Jhon', surname = 'Smith',
#'   dob = '1990-01-15', city = 'London'
#' )
#'
#' il_find_matches(model, new_df, threshold = 0.5)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_find_matches <- function(model, new_records, threshold = 0.85) {
  validate_il_model(model)

  con <- model$con
  dialect <- detect_dialect(con)
  comparisons <- model$spec$comparisons
  params <- model$params$comparisons
  prior <- model$params$prior %||% 0.05
  comp_names <- vapply(comparisons, function(c) c$columns, character(1))
  blocking_rules <- model$spec$blocking_rules
  comp_cols <- unique(comp_names)

  mu <- extract_mu_vectors(params, comp_names)

  # Upload new records to a temporary table for SQL-side blocking
  # Pad missing comparison/blocking columns with NA before registering
  all_needed <- unique(c(
    comp_cols,
    unlist(lapply(blocking_rules, function(r) r$columns))
  ))
  if (is.data.frame(new_records)) {
    for (col in setdiff(all_needed, names(new_records))) {
      new_records[[col]] <- NA_character_
    }
  }
  tbl_new <- '__il_find_new'
  reg <- register_data(new_records,
    con = con, tbl_name = tbl_new,
    add_unique_id = TRUE
  )
  on.exit(drop_registered(con, tbl_new), add = TRUE)

  tbl_existing <- model$data$tbl_l

  if (dialect_has_fuzzy_sql(dialect)) {
    # SQL-first: compute gammas in database
    gamma_exprs <- vapply(comparisons, function(comp) {
      expr <- sql_gamma_case(comp, dialect)
      glue::glue('{expr} AS gamma_{comp$columns}')
    }, character(1))
    gamma_select <- paste(gamma_exprs, collapse = ', ')

    # TF SELECT expressions
    tf_cols <- tf_columns(comparisons)
    tf_select <- sql_tf_select_exprs(tf_cols)
    if (!is.null(tf_select)) {
      gamma_select <- paste(gamma_select, tf_select, sep = ', ')
    }

    if (length(blocking_rules) > 0L) {
      block_parts <- vapply(blocking_rules, function(br) {
        cond <- build_blocking_condition(br$columns, br$where,
                                          transform = br$transform,
                                          dialect = dialect)
        glue::glue(
          'SELECT l.unique_id AS l_unique_id, r.unique_id AS r_unique_id, ',
          '{gamma_select} ',
          'FROM {tbl_new} l, {tbl_existing} r ',
          'WHERE {cond}'
        )
      }, character(1))
      inner <- paste(block_parts, collapse = ' UNION ')
    } else {
      inner <- glue::glue(
        'SELECT l.unique_id AS l_unique_id, r.unique_id AS r_unique_id, ',
        '{gamma_select} ',
        'FROM {tbl_new} l, {tbl_existing} r'
      )
    }
    sql <- glue::glue('SELECT DISTINCT * FROM ({inner}) AS pairs')
    result_raw <- DBI::dbGetQuery(con, sql)

    if (nrow(result_raw) == 0L) {
      return(tibble::tibble(
        unique_id_l = character(0), unique_id_r = character(0),
        match_weight = numeric(0), match_probability = numeric(0)
      ))
    }

    gamma_cols <- paste0('gamma_', comp_names)
    gamma_mat <- as.matrix(result_raw[, gamma_cols, drop = FALSE])
    storage.mode(gamma_mat) <- 'integer'
    colnames(gamma_mat) <- comp_names

    match_weight <- score_gamma_matrix(gamma_mat, mu)

    # Apply TF adjustments
    if (length(tf_cols) > 0L) {
      tf_col_names <- c(
        paste0('tf_', tf_cols, '_l'),
        paste0('tf_', tf_cols, '_r')
      )
      present <- intersect(tf_col_names, names(result_raw))
      if (length(present) > 0L) {
        tf_data <- result_raw[, present, drop = FALSE]
        tf_adj <- compute_tf_adjustment(gamma_mat, tf_data, comparisons, mu)
        match_weight <- match_weight + tf_adj
      }
    }

    match_probability <- weight_to_probability(match_weight, prior)

    result <- tibble::tibble(
      unique_id_l = result_raw$l_unique_id,
      unique_id_r = result_raw$r_unique_id,
      match_weight = match_weight,
      match_probability = match_probability
    )
  } else {
    # Fallback: R-side gamma computation
    block_cols <- unique(unlist(lapply(blocking_rules, function(r) r$columns)))
    needed_cols <- unique(c('unique_id', comp_cols, block_cols))
    new_cols <- intersect(needed_cols, names(new_records))
    # Select only columns that exist in both new_records (l) and existing (r)
    existing_cols <- model$data$columns
    r_cols <- intersect(needed_cols, existing_cols)
    sel_l <- paste(glue::glue('l.{new_cols} AS l_{new_cols}'), collapse = ', ')
    sel_r <- paste(glue::glue('r.{r_cols} AS r_{r_cols}'), collapse = ', ')

    all_pair_frames <- list()
    if (length(blocking_rules) > 0L) {
      for (br in blocking_rules) {
        block_where <- build_blocking_condition(br$columns, br$where,
                                                transform = br$transform,
                                                dialect = dialect)
        sql <- glue::glue(
          'SELECT {sel_l}, {sel_r} FROM {tbl_new} l, {tbl_existing} r ',
          'WHERE {block_where}'
        )
        bp <- DBI::dbGetQuery(con, sql)
        if (nrow(bp) > 0L) all_pair_frames <- c(all_pair_frames, list(bp))
      }
    } else {
      sql <- glue::glue(
        'SELECT {sel_l}, {sel_r} FROM {tbl_new} l, {tbl_existing} r'
      )
      bp <- DBI::dbGetQuery(con, sql)
      if (nrow(bp) > 0L) all_pair_frames <- list(bp)
    }

    if (length(all_pair_frames) == 0L) {
      return(tibble::tibble(
        unique_id_l = character(0), unique_id_r = character(0),
        match_weight = numeric(0), match_probability = numeric(0)
      ))
    }

    pairs <- do.call(rbind, all_pair_frames)
    pair_key <- paste(pairs$l_unique_id, pairs$r_unique_id, sep = '||')
    pairs <- pairs[!duplicated(pair_key), , drop = FALSE]

    gamma_mat <- compute_gamma_matrix(pairs, comparisons)
    match_weight <- score_gamma_matrix(gamma_mat, mu)

    # Apply TF adjustments (R-side)
    tf_cols <- tf_columns(comparisons)
    if (length(tf_cols) > 0L) {
      tf_data <- lookup_tf_r(model, pairs, tf_cols)
      tf_adj <- compute_tf_adjustment(gamma_mat, tf_data, comparisons, mu)
      match_weight <- match_weight + tf_adj
    }

    match_probability <- weight_to_probability(match_weight, prior)

    result <- tibble::tibble(
      unique_id_l = pairs$l_unique_id,
      unique_id_r = pairs$r_unique_id,
      match_weight = match_weight,
      match_probability = match_probability
    )
  }

  result <- result[result$match_probability >= threshold, , drop = FALSE]

  if (nrow(result) == 0L) {
    return(tibble::tibble(
      unique_id_l = character(0), unique_id_r = character(0),
      match_weight = numeric(0), match_probability = numeric(0)
    ))
  }

  tibble::as_tibble(result)
}
