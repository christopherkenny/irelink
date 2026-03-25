#' Estimate Match (m) Parameters from a Label Column
#'
#' Learns the m probabilities from a ground-truth identifier column
#' (e.g., Social Security Number) present in the input data. Records
#' sharing the same label value are treated as true matches. This is an
#' alternative to [il_estimate_m_from_labels()], which requires a
#' separate table of pairwise labels.
#'
#' @param model An `il_model` object (piped in).
#' @param label_col The unquoted name of a column in the input data
#'   containing ground-truth entity identifiers.
#'
#' @return An updated `il_model` with estimated m parameters.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_model(voters, spec = spec, con = con) |>
#'   il_estimate_u() |>
#'   il_estimate_m_from_column(true_person_id)
#' }
il_estimate_m_from_column <- function(model, label_col) {
  validate_il_model(model)
  col_name <- rlang::as_name(rlang::enquo(label_col))
  con <- model$con
  tbl <- model$data$tbl_l
  comparisons <- model$spec$comparisons
  cols <- model$data$columns

  # Get data
  data <- DBI::dbReadTable(con, tbl)
  if (!col_name %in% names(data)) {
    cli::cli_abort("Column {.field {col_name}} not found in the data.")
  }

  # Generate all within-cluster pairs
  labels <- data[[col_name]]
  unique_labels <- unique(labels[!is.na(labels)])

  pair_rows <- list()
  for (lab in unique_labels) {
    cluster_rows <- which(labels == lab)
    if (length(cluster_rows) < 2L) next
    combos <- utils::combn(cluster_rows, 2)
    for (k in seq_len(ncol(combos))) {
      i <- combos[1, k]
      j <- combos[2, k]
      pair <- as.data.frame(c(
        stats::setNames(as.list(data[i, ]), paste0("l_", names(data))),
        stats::setNames(as.list(data[j, ]), paste0("r_", names(data)))
      ))
      pair_rows <- c(pair_rows, list(pair))
    }
  }

  if (length(pair_rows) == 0L) {
    cli::cli_abort("No within-cluster pairs found for column {.field {col_name}}.")
  }

  pairs <- do.call(rbind, pair_rows)
  gamma_mat <- compute_gamma_matrix(pairs, comparisons)

  comp_names <- colnames(gamma_mat)
  m_match <- colMeans(gamma_mat)
  m_nonmatch <- 1 - m_match

  if (!is.null(model$params$comparisons)) {
    params <- model$params$comparisons
    for (j in seq_along(comp_names)) {
      cn <- comp_names[j]
      params$m[params$comparison == cn & params$level == "match"] <- m_match[j]
      params$m[params$comparison == cn & params$level == "non_match"] <- m_nonmatch[j]
    }
    model$params$comparisons <- params
  } else {
    model$params$comparisons <- tibble::tibble(
      comparison = rep(comp_names, each = 2L),
      level = rep(c("match", "non_match"), times = length(comp_names)),
      m = as.numeric(rbind(m_match, m_nonmatch)),
      u = NA_real_
    )
  }

  model$trained <- TRUE
  model
}
