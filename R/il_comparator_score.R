#' Batch String Similarity Scores
#'
#' Computes string-similarity metrics between two columns of a data frame
#' or database table. Useful for profiling data quality and choosing
#' comparison thresholds. Rows where either column is missing are omitted.
#'
#' With `con = NULL`, all metrics are computed in R with
#' [stringdist::stringdist()]. With a [duckdb::duckdb()] or PostgreSQL connection,
#' computation is pushed to SQL. SQL backends return the same column schema
#' but may leave unsupported metrics as `NA`: DuckDB currently computes
#' `jaro_winkler`, `jaro`, `levenshtein`, and `jaccard`; PostgreSQL computes
#' `levenshtein` and a `jaro_winkler` compatibility column backed by trigram
#' `similarity()`.
#'
#' @param .data A data frame or character table name. Table names require
#'   `con`.
#' @param col_1,col_2 Column names (unquoted or character).
#' @param con A DBI connection from [DBI::dbConnect()]. If `NULL`, uses R-side computation.
#'
#' @return A [tibble::tibble()] with the two input columns and metric columns
#'   `jaro_winkler`, `jaro`, `levenshtein`, `jaccard`, and `cosine`.
#'   Unsupported SQL-backend metrics are present as `NA`. The result has S3
#'   class `il_comparator_score`.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   name_l = c('John', 'Jane', 'Bob'),
#'   name_r = c('Jon', 'Janet', 'Bobby')
#' )
#' il_comparator_score(df, name_l, name_r)
il_comparator_score <- function(.data, col_1, col_2, con = NULL) {
  col_1 <- as.character(rlang::ensym(col_1))
  col_2 <- as.character(rlang::ensym(col_2))

  use_sql <- !is.null(con) &&
    DBI::dbIsValid(con) &&
    detect_dialect(con) %in% c('duckdb', 'postgres')

  if (use_sql) {
    result <- comparator_score_sql(.data, col_1, col_2, con)
  } else {
    result <- comparator_score_r(.data, col_1, col_2)
  }

  add_class(result, 'il_comparator_score')
}

#' SQL-path comparator score
#' @noRd
comparator_score_sql <- function(.data, col_1, col_2, con) {
  tbl_name <- il_scratch_table_name('comparator')
  if (is.data.frame(.data)) {
    DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl_name}'))
    DBI::dbWriteTable(con, tbl_name, .data)
    on.exit(
      DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {tbl_name}')),
      add = TRUE
    )
  } else {
    tbl_name <- as.character(.data)
  }

  dialect <- detect_dialect(con)
  qtbl <- sql_quote_identifier(tbl_name)
  qcol_1 <- sql_quote_identifier(col_1)
  qcol_2 <- sql_quote_identifier(col_2)
  if (dialect == 'duckdb') {
    sql <- glue::glue(
      'SELECT {qcol_1}, {qcol_2}, ',
      '  jaro_winkler_similarity({qcol_1}, {qcol_2}) AS jaro_winkler, ',
      '  jaro_similarity({qcol_1}, {qcol_2}) AS jaro, ',
      '  levenshtein({qcol_1}, {qcol_2}) AS levenshtein, ',
      '  jaccard({qcol_1}, {qcol_2}) AS jaccard ',
      'FROM {qtbl} ',
      'WHERE {qcol_1} IS NOT NULL AND {qcol_2} IS NOT NULL'
    )
  } else {
    # PostgreSQL: pg_trgm provides similarity(); levenshtein from fuzzystrmatch
    sql <- glue::glue(
      'SELECT {qcol_1}, {qcol_2}, ',
      '  similarity({qcol_1}, {qcol_2}) AS jaro_winkler, ',
      '  levenshtein({qcol_1}, {qcol_2}) AS levenshtein ',
      'FROM {qtbl} ',
      'WHERE {qcol_1} IS NOT NULL AND {qcol_2} IS NOT NULL'
    )
    cli::cli_warn(c(
      'PostgreSQL provides limited similarity functions.',
      'i' = paste(
        'Only {.val jaro_winkler} (compatibility alias for PostgreSQL trigram',
        'similarity) and {.val levenshtein} are computed in SQL.'
      ),
      'i' = 'Use {.code con = NULL} for all 5 metrics via R-side {.pkg stringdist}.'
    ))
  }

  result <- tibble::as_tibble(DBI::dbGetQuery(con, sql))

  # Fill missing metrics with NA for consistent column set
  for (col in c('jaro_winkler', 'jaro', 'levenshtein', 'jaccard', 'cosine')) {
    if (!col %in% names(result)) result[[col]] <- NA_real_
  }
  result
}

#' R-path comparator score
#' @noRd
comparator_score_r <- function(.data, col_1, col_2) {
  if (!is.data.frame(.data)) {
    cli::cli_abort('Provide a {.arg con} argument for table references.')
  }
  a <- as.character(.data[[col_1]])
  b <- as.character(.data[[col_2]])
  valid <- !is.na(a) & !is.na(b)
  a <- a[valid]
  b <- b[valid]

  result <- tibble::tibble(
    x1__ = a,
    x2__ = b,
    jaro_winkler = 1 - stringdist::stringdist(a, b, method = 'jw', p = 0.1),
    jaro = 1 - stringdist::stringdist(a, b, method = 'jw', p = 0),
    levenshtein = as.integer(stringdist::stringdist(a, b, method = 'lv')),
    jaccard = 1 - stringdist::stringdist(a, b, method = 'jaccard', q = 2),
    cosine = 1 - stringdist::stringdist(a, b, method = 'cosine', q = 2)
  )
  names(result)[1:2] <- c(col_1, col_2)
  result
}

#' Comparator Score Threshold Chart
#'
#' Shows the distribution of pairwise similarity scores and highlights
#' which pairs exceed a given threshold.
#'
#' @param .data A data frame or table name.
#' @param col_1,col_2 Column names (unquoted or character).
#' @param similarity_threshold Numeric threshold for similarity metrics
#'   (>= to include). Applies to jaro_winkler, jaro, jaccard, cosine.
#' @param distance_threshold Integer threshold for distance metrics
#'   (<= to include). Applies to levenshtein.
#' @param con A DBI connection from [DBI::dbConnect()]. If `NULL`, uses R-side computation.
#'
#' @return A [ggplot2::ggplot()] object.
#' @export
il_comparator_threshold_chart <- function(
  .data,
  col_1,
  col_2,
  similarity_threshold = NULL,
  distance_threshold = NULL,
  con = NULL
) {
  scores <- il_comparator_score(
    .data,
    !!rlang::ensym(col_1),
    !!rlang::ensym(col_2),
    con = con
  )
  class(scores) <- setdiff(class(scores), 'il_comparator_score')

  sim_cols <- intersect(
    c('jaro_winkler', 'jaro', 'jaccard', 'cosine'),
    names(scores)
  )
  dist_cols <- intersect(c('levenshtein'), names(scores))

  if (!is.null(similarity_threshold) && length(sim_cols) > 0L) {
    long_sim <- reshape_long(scores, sim_cols, 'metric', 'score')
    long_sim$above <- long_sim$score >= similarity_threshold
  } else {
    long_sim <- NULL
  }

  if (!is.null(distance_threshold) && length(dist_cols) > 0L) {
    long_dist <- reshape_long(scores, dist_cols, 'metric', 'score')
    long_dist$above <- long_dist$score <= distance_threshold
  } else {
    long_dist <- NULL
  }

  long <- rbind(long_sim, long_dist)
  if (is.null(long) || nrow(long) == 0L) {
    cli::cli_abort(
      'Provide at least one of {.arg similarity_threshold} or {.arg distance_threshold}.'
    )
  }

  long |>
    ggplot2::ggplot() +
    ggplot2::geom_histogram(
      ggplot2::aes(x = .data$score, fill = .data$above),
      bins = 30,
      colour = 'white'
    ) +
    ggplot2::facet_wrap(~metric, scales = 'free') +
    ggplot2::scale_fill_manual(
      values = c('TRUE' = '#2171b5', 'FALSE' = '#bdbdbd'),
      labels = c('TRUE' = 'Above', 'FALSE' = 'Below'),
      name = 'Threshold'
    ) +
    ggplot2::labs(
      x = 'Score',
      y = 'Count',
      title = 'Comparator Score Threshold Analysis'
    ) +
    ggplot2::theme_minimal()
}

#' Phonetic Match Chart
#'
#' Visualizes phonetic coding agreement between two columns. Shows how
#' Soundex groupings match across pairs.
#'
#' @param .data A data frame or character table name.
#' @param col_1,col_2 Column names (unquoted or character).
#' @param con A DBI connection from [DBI::dbConnect()]. If provided and [duckdb::duckdb()] or
#'   PostgreSQL, computes Soundex in SQL.
#'
#' @return A [ggplot2::ggplot()] object.
#' @export
il_phonetic_chart <- function(.data, col_1, col_2, con = NULL) {
  col_1 <- as.character(rlang::ensym(col_1))
  col_2 <- as.character(rlang::ensym(col_2))

  use_sql <- !is.null(con) &&
    DBI::dbIsValid(con) &&
    detect_dialect(con) %in% c('duckdb', 'postgres')

  if (use_sql) {
    tbl_name <- il_scratch_table_name('phonetic')
    if (is.data.frame(.data)) {
      qtbl <- sql_quote_identifier(tbl_name)
      DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {qtbl}'))
      DBI::dbWriteTable(con, tbl_name, .data)
      on.exit(
        DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {qtbl}')),
        add = TRUE
      )
    } else {
      tbl_name <- as.character(.data)
    }

    dialect <- detect_dialect(con)
    if (dialect == 'duckdb') {
      register_phonetic_macros(con)
    }
    sx_fn <- 'soundex'
    if (dialect == 'duckdb') {
      sx_fn <- 'il_soundex'
    }
    qtbl <- sql_quote_identifier(tbl_name)
    qcol_1 <- sql_quote_identifier(col_1)
    qcol_2 <- sql_quote_identifier(col_2)

    sql <- glue::glue(
      'SELECT {qcol_1} AS {qcol_1}, {qcol_2} AS {qcol_2}, ',
      '  {sx_fn}({qcol_1}) AS soundex_1, ',
      '  {sx_fn}({qcol_2}) AS soundex_2, ',
      '  {sx_fn}({qcol_1}) = {sx_fn}({qcol_2}) AS soundex_match ',
      'FROM {qtbl} ',
      'WHERE {qcol_1} IS NOT NULL AND {qcol_2} IS NOT NULL'
    )
    df <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  } else {
    if (!is.data.frame(.data)) {
      cli::cli_abort('Provide a {.arg con} argument for table references.')
    }
    a <- as.character(.data[[col_1]])
    b <- as.character(.data[[col_2]])
    valid <- !is.na(a) & !is.na(b)

    df <- tibble::tibble(
      x1__ = a[valid],
      x2__ = b[valid],
      soundex_1 = il_soundex(a[valid]),
      soundex_2 = il_soundex(b[valid]),
      soundex_match = il_soundex(a[valid]) == il_soundex(b[valid])
    )
    names(df)[1:2] <- c(col_1, col_2)
  }

  df |>
    ggplot2::ggplot() +
    ggplot2::geom_tile(
      ggplot2::aes(
        x = .data$soundex_1,
        y = .data$soundex_2,
        fill = .data$soundex_match
      ),
      colour = 'white'
    ) +
    ggplot2::scale_fill_manual(
      values = c('TRUE' = '#2171b5', 'FALSE' = '#fee0d2'),
      name = 'Match'
    ) +
    ggplot2::labs(
      x = paste('Soundex of', col_1),
      y = paste('Soundex of', col_2),
      title = 'Phonetic Match Chart'
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

#' Reshape wide to long (base R helper)
#' @noRd
reshape_long <- function(df, cols, names_to, values_to) {
  rows <- lapply(cols, function(col) {
    out <- df[, setdiff(names(df), cols), drop = FALSE]
    out[[names_to]] <- col
    out[[values_to]] <- df[[col]]
    out
  })
  do.call(rbind, rows)
}
