#' Create a Linkage Model
#'
#' Binds one or more data frames to a specification and a database
#' connection, producing an untrained model. This is analogous to how
#' [dplyr::tbl()] binds a connection to a table name and returns a lazy
#' reference.
#'
#' @param .data A data frame or tibble. The first (or only) input dataset.
#' @param ... Additional data frames for multi-table linkage.
#' @param spec An `il_spec` object built with [il_spec()], [il_compare()],
#'   and [il_block_on()].
#' @param con A DBI connection object (e.g., from
#'   `DBI::dbConnect(duckdb::duckdb())`).
#' @param link_type One of `"dedupe"` (default), `"link"`, or
#'   `"link_and_dedupe"`.
#'
#' @return An untrained `il_model` object, ready for training verbs.
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
#'   il_block_on(surname)
#'
#' model <- il_model(df, spec = spec, con = con)
#' DBI::dbDisconnect(con)
il_model <- function(.data, ..., spec, con,
                     link_type = c("dedupe", "link", "link_and_dedupe")) {
  link_type <- match.arg(link_type)
  extra_dfs <- list(...)

  validate_il_spec(spec)

  if (nrow(.data) == 0L) {
    cli::cli_abort("Cannot create a model from a zero-row data frame.")
  }

  # Convert factors to character
  .data <- factor_to_char(.data)

  # Validate columns referenced in spec exist in data
  spec_cols <- get_spec_columns(spec)
  missing_cols <- setdiff(spec_cols, names(.data))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      "Column{?s} {.field {missing_cols}} referenced in the spec but not found in the data."
    )
  }

  if (link_type == "link" && length(extra_dfs) == 0L) {
    cli::cli_abort(
      "{.arg link_type} is {.val link} but only one dataset was provided. Supply a second data frame."
    )
  }

  # Upload data to database
  tbl_name_l <- "__il_data_l"
  DBI::dbWriteTable(con, tbl_name_l, .data, overwrite = TRUE)

  tbl_name_r <- NULL
  if (length(extra_dfs) > 0L) {
    extra_dfs[[1]] <- factor_to_char(extra_dfs[[1]])
    tbl_name_r <- "__il_data_r"
    DBI::dbWriteTable(con, tbl_name_r, extra_dfs[[1]], overwrite = TRUE)
  }

  data_info <- list(
    n_records_l = nrow(.data),
    n_records_r = if (!is.null(tbl_name_r)) nrow(extra_dfs[[1]]) else NULL,
    tbl_l = tbl_name_l,
    tbl_r = tbl_name_r,
    columns = names(.data)
  )

  new_il_model(
    spec = spec,
    data = data_info,
    con = con,
    link_type = link_type,
    params = list(),
    trained = FALSE
  )
}

#' Print an irelink Model
#'
#' Displays a human-readable summary of the model's type, data, training
#' status, comparisons, and blocking rules.
#'
#' @param x An `il_model` object.
#' @param ... Additional arguments passed to [print()].
#'
#' @return `x`, invisibly.
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
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' print(model)
#' DBI::dbDisconnect(con)
print.il_model <- function(x, ...) {
  status <- if (x$trained) "Trained" else "Untrained"
  n_records <- x$data$n_records_l
  n_comparisons <- length(x$spec$comparisons)
  n_blocking <- length(x$spec$blocking_rules)

  cat("irelink Model\n")
  cat(sprintf("  Status: %s\n", status))
  cat(sprintf("  Link type: %s\n", x$link_type))
  cat(sprintf("  Records: %d\n", n_records))
  if (!is.null(x$data$n_records_r)) {
    cat(sprintf("  Records (right): %d\n", x$data$n_records_r))
  }
  cat(sprintf("  Comparisons: %d\n", n_comparisons))
  cat(sprintf("  Blocking rules: %d\n", n_blocking))
  invisible(x)
}

#' Summarise an irelink Model
#'
#' Prints a detailed table of trained parameters including m and u
#' probabilities, match weights, and the prior match probability for
#' each comparison level.
#'
#' @param object An `il_model` object.
#' @param ... Additional arguments passed to [summary()].
#'
#' @return A summary object, invisibly.
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
#'   il_block_on(surname)
#' model <- il_model(df, spec = spec, con = con)
#' summary(model)
#' DBI::dbDisconnect(con)
summary.il_model <- function(object, ...) {
  print.il_model(object, ...)
  if (object$trained) {
    cat("\n  Parameters:\n")
    params <- object$params
    if (length(params) > 0L) {
      for (nm in names(params)) {
        cat(sprintf("    %s: %s\n", nm, format(params[[nm]])))
      }
    }
  }
  invisible(object)
}

#' Test if an Object is an irelink Model
#'
#' Returns `TRUE` if `x` inherits from class `il_model`.
#'
#' @param x An object to test.
#'
#' @return A single logical value.
#' @export
#'
#' @examples
#' is_il_model(il_spec())
is_il_model <- function(x) {
  inherits(x, "il_model")
}
