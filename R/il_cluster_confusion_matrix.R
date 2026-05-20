#' Cluster-Level Confusion Matrix for Deduplication
#'
#' Computes a record-level confusion matrix after clustering predicted
#' matches into entities. A record is treated as "duplicated" if it is not
#' the first record in its predicted cluster, and likewise for the
#' ground-truth `labels_col`.
#'
#' For DuckDB and PostgreSQL backends, pair scoring and clustering are
#' pushed into SQL where possible. The final summary still returns a
#' one-row tibble in R.
#'
#' @param model A trained `il_model` object for a deduplication task.
#' @param labels_col String naming the ground-truth cluster/entity column
#'   in the model's source data.
#' @param threshold Match-probability threshold passed to [predict()].
#'   Defaults to `0.85`.
#' @param method Clustering method passed to [il_cluster()].
#' @param ties_method Tie handling for `method = "best_link"`, passed to
#'   [il_cluster()].
#' @param source_dataset Optional source-dataset mapping passed to
#'   [il_cluster()]. If supplied, it must cover every `unique_id` in the
#'   predicted pairs, and duplicate `unique_id` mappings are not allowed.
#'
#' @return A one-row tibble with columns `threshold`, `tp`, `fp`, `fn`,
#'   `tn`, `precision`, `recall`, and `f1`.
#' @export
#'
#' @examples
#' df <- data.frame(
#'   unique_id = 1:5,
#'   first_name = c('John', 'John', 'Mary', 'Bob', 'Bob'),
#'   surname = c('Smith', 'Smith', 'Jones', 'Brown', 'Brown'),
#'   cluster = c(1, 1, 2, 3, 4)
#' )
#' con <- DBI::dbConnect(duckdb::duckdb())
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_exact()) |>
#'   il_compare(surname, cl_exact()) |>
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' model <- il_estimate_u(model)
#' model <- il_estimate_em(model, block_on(surname))
#'
#' il_cluster_confusion_matrix(model, labels_col = 'cluster', threshold = 0.85)
#' DBI::dbDisconnect(con, shutdown = TRUE)
il_cluster_confusion_matrix <- function(
  model,
  labels_col,
  threshold = 0.85,
  method = c('connected', 'best_link'),
  ties_method = c('lowest_id', 'drop'),
  source_dataset = NULL
) {
  validate_il_model(model)
  method <- match.arg(method)
  ties_method <- match.arg(ties_method)

  if (!identical(model$link_type %||% 'dedupe', 'dedupe')) {
    cli::cli_abort(
      '{.fn il_cluster_confusion_matrix} currently supports deduplication models only.'
    )
  }
  if (
    !is.character(labels_col) || length(labels_col) != 1L || is.na(labels_col)
  ) {
    cli::cli_abort('{.arg labels_col} must be a single column name.')
  }
  if (!(labels_col %in% model$data$columns)) {
    cli::cli_abort(
      '{.arg labels_col} ({.val {labels_col}}) was not found in the model data.'
    )
  }

  con <- model$con
  dialect <- detect_dialect(con)
  use_sql <- dialect_has_fuzzy_sql(dialect)

  counts <- if (use_sql) {
    pairs <- predict(model, threshold = threshold, collect = FALSE)
    clusters_tbl <- cluster_assignments_lazy_sql(
      pairs,
      threshold = NULL,
      method = method,
      ties_method = ties_method,
      source_dataset = source_dataset
    )
    on.exit(drop_registered(con, clusters_tbl), add = TRUE)
    cluster_confusion_counts_sql(model, clusters_tbl, labels_col)
  } else {
    pairs <- predict(model, threshold = threshold, collect = TRUE)
    clusters <- il_cluster(
      pairs,
      method = method,
      ties_method = ties_method,
      source_dataset = source_dataset
    )
    cluster_confusion_counts_r(model, clusters, labels_col)
  }

  summarise_confusion_counts(counts, threshold = threshold) |>
    add_class('il_cluster_confusion_matrix')
}

#' Compute cluster-level confusion counts in SQL
#' @noRd
cluster_confusion_counts_sql <- function(model, clusters_tbl, labels_col) {
  con <- model$con
  tbl <- model$data$tbl_l
  qtbl <- sql_quote_identifier(tbl)
  qclusters_tbl <- sql_quote_identifier(clusters_tbl)
  qlabels_col <- sql_quote_identifier(labels_col)

  sql <- glue::glue(
    'WITH base AS (',
    '  SELECT CAST(d.unique_id AS VARCHAR) AS unique_id, ',
    '         d.{qlabels_col} AS true_group, ',
    "         COALESCE(c.cluster_id, 'singleton_' || CAST(d.unique_id AS VARCHAR)) AS pred_group ",
    '  FROM {qtbl} d ',
    '  LEFT JOIN {qclusters_tbl} c ',
    '    ON CAST(d.unique_id AS VARCHAR) = c.unique_id',
    '), flags AS (',
    '  SELECT unique_id, ',
    '         CASE ',
    '           WHEN true_group IS NOT NULL ',
    '             AND ROW_NUMBER() OVER (PARTITION BY true_group ORDER BY unique_id) > 1 ',
    '           THEN 1 ELSE 0 END AS true_dup, ',
    '         CASE ',
    '           WHEN ROW_NUMBER() OVER (PARTITION BY pred_group ORDER BY unique_id) > 1 ',
    '           THEN 1 ELSE 0 END AS pred_dup ',
    '  FROM base',
    ') ',
    'SELECT ',
    '  CAST(SUM(CASE WHEN pred_dup = 1 AND true_dup = 1 THEN 1 ELSE 0 END) AS INTEGER) AS tp, ',
    '  CAST(SUM(CASE WHEN pred_dup = 1 AND true_dup = 0 THEN 1 ELSE 0 END) AS INTEGER) AS fp, ',
    '  CAST(SUM(CASE WHEN pred_dup = 0 AND true_dup = 1 THEN 1 ELSE 0 END) AS INTEGER) AS fn, ',
    '  CAST(SUM(CASE WHEN pred_dup = 0 AND true_dup = 0 THEN 1 ELSE 0 END) AS INTEGER) AS tn ',
    'FROM flags'
  )
  counts <- DBI::dbGetQuery(con, sql)
  counts$fn_blocking_miss <- NA_integer_
  tibble::as_tibble(counts)
}

#' Build a SQL table of cluster assignments from lazy predictions
#' @noRd
cluster_assignments_lazy_sql <- function(
  pairs,
  threshold = NULL,
  method = c('connected', 'best_link'),
  ties_method = c('lowest_id', 'drop'),
  source_dataset = NULL
) {
  method <- match.arg(method)
  ties_method <- match.arg(ties_method)
  if (!is.null(threshold)) {
    threshold <- validate_probability_threshold(threshold, 'threshold')
  }
  validate_cluster_pairs(pairs, threshold = threshold, method = method)
  source_dataset <- prepare_cluster_source_dataset(
    source_dataset,
    pairs,
    method = method
  )

  con <- pairs$con
  predicted_tbl <- pairs$predicted_tbl
  cc_prefix <- il_scratch_table_name('cc')
  edges_tbl <- cc_tbl('edges', cc_prefix)
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {edges_tbl}'))

  threshold_where <- ''
  if (!is.null(threshold)) {
    threshold_where <- glue::glue(' WHERE match_probability >= {threshold}')
  }

  DBI::dbExecute(
    con,
    glue::glue(
      'CREATE TABLE {edges_tbl} AS ',
      'SELECT unique_id_l, unique_id_r, match_probability ',
      'FROM {predicted_tbl}{threshold_where}'
    )
  )
  on.exit(drop_registered(con, edges_tbl), add = TRUE)

  cc_output_tbl <- if (method == 'best_link') {
    if (!is.null(source_dataset)) {
      solve_one_to_one_sql(
        con,
        edges_tbl,
        source_dataset = source_dataset,
        ties_method = ties_method,
        collect = FALSE,
        prefix = cc_prefix
      )
    } else {
      filtered_tbl <- sql_best_link_filter(
        con,
        edges_tbl,
        ties_method,
        prefix = cc_prefix
      )
      DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {edges_tbl}'))
      DBI::dbExecute(
        con,
        glue::glue(
          'ALTER TABLE {filtered_tbl} RENAME TO {edges_tbl}'
        )
      )
      solve_cc_sql(con, edges_tbl, collect = FALSE, prefix = cc_prefix)
    }
  } else {
    solve_cc_sql(con, edges_tbl, collect = FALSE, prefix = cc_prefix)
  }
  on.exit(drop_registered(con, cc_output_tbl), add = TRUE)

  final_tbl <- cc_tbl('cluster_eval', cc_prefix)
  DBI::dbExecute(con, glue::glue('DROP TABLE IF EXISTS {final_tbl}'))
  sql <- paste0(
    'CREATE TABLE ',
    final_tbl,
    ' AS ',
    'WITH all_ids AS (',
    '  SELECT DISTINCT CAST(unique_id_l AS VARCHAR) AS unique_id FROM ',
    predicted_tbl,
    ' UNION ',
    '  SELECT DISTINCT CAST(unique_id_r AS VARCHAR) AS unique_id FROM ',
    predicted_tbl,
    ') ',
    'SELECT all_ids.unique_id, ',
    "COALESCE('cluster_' || CAST(cc.cluster_id AS VARCHAR), 'cluster_' || all_ids.unique_id) AS cluster_id ",
    'FROM all_ids ',
    'LEFT JOIN ',
    cc_output_tbl,
    ' cc ',
    '  ON all_ids.unique_id = CAST(cc.node_id AS VARCHAR)'
  )
  DBI::dbExecute(con, sql)

  final_tbl
}

#' Compute cluster-level confusion counts in R
#' @noRd
cluster_confusion_counts_r <- function(model, clusters, labels_col) {
  con <- model$con
  tbl <- model$data$tbl_l
  qtbl <- sql_quote_identifier(tbl)
  qlabels_col <- sql_quote_identifier(labels_col)
  sql <- glue::glue(
    'SELECT unique_id, {qlabels_col} FROM {qtbl} ORDER BY unique_id'
  )
  base <- DBI::dbGetQuery(con, sql)
  base$unique_id <- as.character(base$unique_id)

  cluster_map <- stats::setNames(
    as.character(clusters$cluster_id),
    as.character(clusters$unique_id)
  )
  base$pred_group <- unname(cluster_map[base$unique_id])
  missing_cluster <- is.na(base$pred_group)
  base$pred_group[missing_cluster] <- paste0(
    'singleton_',
    base$unique_id[missing_cluster]
  )

  true_group <- base[[labels_col]]
  true_dup <- !is.na(true_group) & duplicated(true_group)
  pred_dup <- duplicated(base$pred_group)

  tibble::tibble(
    tp = sum(pred_dup & true_dup),
    fp = sum(pred_dup & !true_dup),
    fn = sum(!pred_dup & true_dup),
    tn = sum(!pred_dup & !true_dup),
    fn_blocking_miss = NA_integer_
  )
}
