test_that('il_cluster_confusion_matrix() matches manual record-level counts', {
  con <- test_con()
  on.exit(test_discon(con))

  df <- data.frame(
    unique_id = 1:5,
    first_name = c('John', 'John', 'Mary', 'Bob', 'Bob'),
    surname = c('Smith', 'Smith', 'Jones', 'Brown', 'Brown'),
    cluster = c(1, 1, 2, 3, 4)
  )

  spec <- il_spec() |>
    il_compare(first_name, cl_exact()) |>
    il_compare(surname, cl_exact()) |>
    il_block_on(surname)

  model <- il_model(df, spec = spec, con = con) |>
    il_estimate_u(max_pairs = 1e6) |>
    il_estimate_em(block_on(surname))

  cm <- il_cluster_confusion_matrix(model, labels_col = 'cluster', threshold = 0.85)
  expect_s3_class(cm, 'il_cluster_confusion_matrix')

  pairs <- predict(model, threshold = 0.85)
  clusters <- il_cluster(pairs)
  records <- df
  records$unique_id <- as.character(records$unique_id)
  cluster_map <- stats::setNames(clusters$cluster_id, clusters$unique_id)
  records$cluster_id <- unname(cluster_map[records$unique_id])
  missing_cluster <- is.na(records$cluster_id)
  records$cluster_id[missing_cluster] <- paste0('singleton_', records$unique_id[missing_cluster])
  records$dup_true <- duplicated(records$cluster)
  records$dup_pred <- duplicated(records$cluster_id)

  expect_equal(cm$tp, sum(records$dup_pred & records$dup_true))
  expect_equal(cm$fp, sum(records$dup_pred & !records$dup_true))
  expect_equal(cm$fn, sum(!records$dup_pred & records$dup_true))
  expect_equal(cm$tn, sum(!records$dup_pred & !records$dup_true))
})

test_that('il_cluster_confusion_matrix() errors for non-dedupe models', {
  con <- test_con()
  on.exit(test_discon(con))

  df_a <- data.frame(unique_id = 1:2, name = c('John', 'Mary'), cluster = c(1, 2))
  df_b <- data.frame(unique_id = 3:4, name = c('John', 'Bob'), cluster = c(1, 3))

  spec <- il_spec() |>
    il_compare(name, cl_exact()) |>
    il_block_on(name)

  model <- il_model(df_a, df_b, spec = spec, con = con, link_type = 'link')

  expect_error(
    il_cluster_confusion_matrix(model, labels_col = 'cluster'),
    'deduplication models only'
  )
})
