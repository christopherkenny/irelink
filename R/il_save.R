#' Save a Model to Disk
#'
#' Serialises a trained `il_model` object to a file so that it can be
#' loaded later without re-training.
#'
#' @param model A trained `il_model` object.
#' @param path A file path (character string) where the model will be
#'   saved.
#'
#' @return `model`, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' il_save(model, "my_model.rds")
#' }
il_save <- function(model, path) {
  validate_il_model(model)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg jsonlite} is required for il_save.")
  }

  # Serialize spec into plain lists (strip S3 classes for JSON)
  spec_data <- list(
    comparisons = lapply(model$spec$comparisons, function(cmp) {
      method <- unclass(cmp$method)
      list(
        columns = cmp$columns,
        method = method
      )
    }),
    blocking_rules = lapply(model$spec$blocking_rules, function(br) {
      unclass(br)
    })
  )

  # Serialize params (tibbles become data frames, which jsonlite handles)
  params_data <- model$params
  if (inherits(params_data$comparisons, "tbl_df")) {
    params_data$comparisons <- as.data.frame(params_data$comparisons)
  }
  # Strip any tibbles from history entries
  if (!is.null(params_data$history) && is.list(params_data$history)) {
    params_data$history <- lapply(params_data$history, function(h) {
      if (inherits(h, "tbl_df")) as.data.frame(h) else h
    })
  }

  data_out <- list(
    spec = spec_data,
    params = params_data,
    trained = model$trained,
    link_type = model$link_type,
    data_info = list(
      n_records_l = model$data$n_records_l,
      n_records_r = model$data$n_records_r,
      columns = model$data$columns
    )
  )

  jsonlite::write_json(data_out, path, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", digits = NA)
  invisible(model)
}

#' Load a Saved Model
#'
#' Reads a previously saved `il_model` object from disk. The loaded model
#' is ready for prediction without re-training, though a fresh database
#' connection may need to be supplied.
#'
#' @param path A file path (character string) to a saved model.
#'
#' @return An `il_model` object.
#' @export
#'
#' @examples
#' \dontrun{
#' model <- il_load("my_model.rds")
#' }
il_load <- function(path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg jsonlite} is required for il_load.")
  }
  if (!file.exists(path)) {
    cli::cli_abort("File {.file {path}} does not exist.")
  }

  raw <- jsonlite::read_json(path, simplifyVector = TRUE)

  # Reconstruct spec
  comparisons <- lapply(seq_len(NROW(raw$spec$comparisons)), function(i) {
    cmp_data <- if (is.data.frame(raw$spec$comparisons)) {
      as.list(raw$spec$comparisons[i, ])
    } else {
      raw$spec$comparisons[[i]]
    }
    method_data <- cmp_data$method
    if (is.character(method_data) || is.list(method_data)) {
      method_data <- as.list(method_data)
    }
    method <- structure(method_data, class = "il_comparison_level")
    list(columns = cmp_data$columns, method = method)
  })

  blocking_rules <- lapply(seq_len(NROW(raw$spec$blocking_rules)), function(i) {
    br_data <- if (is.data.frame(raw$spec$blocking_rules)) {
      as.list(raw$spec$blocking_rules[i, ])
    } else {
      raw$spec$blocking_rules[[i]]
    }
    structure(br_data, class = "il_blocking_rule")
  })

  spec <- new_il_spec(comparisons = comparisons, blocking_rules = blocking_rules)

  # Reconstruct params
  params <- raw$params
  if (!is.null(params$comparisons)) {
    params$comparisons <- tibble::as_tibble(as.data.frame(params$comparisons))
  }
  if (!is.null(params$prior) && length(params$prior) == 1L) {
    params$prior <- as.numeric(params$prior)
  }

  data_info <- raw$data_info
  if (!is.null(data_info)) {
    data_info <- as.list(data_info)
  } else {
    data_info <- list()
  }

  new_il_model(
    spec = spec,
    data = data_info,
    con = NULL,
    link_type = raw$link_type %||% "dedupe",
    params = params,
    trained = isTRUE(raw$trained)
  )
}
