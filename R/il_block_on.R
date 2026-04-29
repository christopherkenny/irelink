#' Add a Prediction Blocking Rule
#'
#' Adds an equality-based blocking rule to a specification. During
#' prediction, only record pairs that agree on the blocking columns are
#' scored. Multiple calls are OR-ed together; within a single call,
#' columns are AND-ed. This mirrors [dplyr::join_by()] where multiple
#' conditions inside one call are AND-ed.
#'
#' @param spec An `il_spec` object (piped in).
#' @param ... Columns for equality blocking (AND-ed within one call).
#'   Each entry is either:
#'   * A bare column name, e.g. `surname`.
#'   * A `column ~ transform` formula, e.g. `first_name ~ il_substr(1, 3)`,
#'     which applies the transform to that column before the equality check.
#'     Mix bare names and formulas freely within one call.
#' @param .where An optional raw SQL string for non-equality blocking
#'   conditions. Defaults to `NULL`.
#' @param .transform An optional transform applied to every column that does
#'   not already have a formula transform. Can be a single function (e.g.
#'   [il_soundex]) or a named list of functions for per-column transforms.
#'   Formula transforms in `...` take precedence over `.transform`.
#'
#' @param .explode An optional character vector of column names containing
#'   arrays (list columns) to unnest before blocking. Each array element
#'   becomes a separate row for the blocking join. Requires a DuckDB or
#'   PostgreSQL backend. Defaults to `NULL`.
#'
#' @return An updated `il_spec` (a new copy; the input is not modified).
#' @export
#'
#' @examples
#' # Block on state OR first name (two calls = OR)
#' spec <- il_spec() |>
#'   il_block_on(state) |>
#'   il_block_on(first_name)
#'
#' # Block where state AND year both match (one call = AND)
#' spec <- il_spec() |>
#'   il_block_on(state, year)
#'
#' # Per-column substring blocking with formula syntax
#' spec <- il_spec() |>
#'   il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
#'
#' # Mix: substr on one column, plain match on another
#' spec <- il_spec() |>
#'   il_block_on(postcode_fake ~ il_substr(1, 3), dob)
#'
#' # Same transform on all columns
#' spec <- il_spec() |>
#'   il_block_on(first_name, .transform = il_soundex)
#'
#' # Explode array columns before blocking
#' spec <- il_spec() |>
#'   il_block_on(email, .explode = 'email')
il_block_on <- function(spec, ..., .where = NULL, .transform = NULL,
                        .explode = NULL) {
  if (!inherits(spec, 'il_spec')) {
    cli::cli_abort(
      '{.arg spec} must be an {.cls il_spec} object, not {.obj_type_friendly {spec}}.',
      class = 'il_error_type'
    )
  }
  validate_transform_arg(.transform)
  if (!is.null(.explode) && !is.character(.explode)) {
    cli::cli_abort(
      '{.arg .explode} must be a character vector or {.code NULL}, not {.obj_type_friendly {(.explode)}}.',
      class = 'il_error_type'
    )
  }
  parsed <- parse_blocking_cols(rlang::enquos(...))
  transform <- merge_blocking_transforms(parsed$per_col_tfs, .transform, parsed$columns)
  rule <- structure(
    list(
      columns = parsed$columns, where = .where, transform = transform,
      explode = .explode
    ),
    class = 'il_blocking_rule'
  )
  spec$blocking_rules <- c(spec$blocking_rules, list(rule))
  spec
}

#' Create a Training-Time Blocking Rule
#'
#' Creates a blocking rule for use inside training verbs such as
#' [il_estimate_em()] and [il_estimate_prior()]. This is distinct from
#' [il_block_on()], which adds prediction-time blocking to a specification.
#' Analogous to [dplyr::join_by()] — a specification object that describes
#' how to partition pairs during training.
#'
#' @param ... Column names (bare or `column ~ transform` formulas). See
#'   [il_block_on()] for details on the formula syntax. Columns are AND-ed
#'   within a single `block_on()` call.
#' @param .where An optional raw SQL string for non-equality blocking
#'   conditions (e.g., `"levenshtein(l.dob, r.dob) <= 1"`). When
#'   supplied alongside column names, the column equalities and the SQL
#'   condition are AND-ed together.
#' @param .transform An optional transform applied to every column that does
#'   not already have a formula transform. See [il_block_on()] for details.
#'
#' @param .explode An optional character vector of array column names to
#'   unnest before blocking. See [il_block_on()] for details.
#'
#' @return A blocking-rule object for use in training verbs.
#' @export
#'
#' @examples
#' block_on(first_name, surname)
#'
#' # Fuzzy SQL conditions
#' block_on(first_name, .where = 'levenshtein(l.dob, r.dob) <= 1')
#'
#' # Phonetic blocking
#' block_on(first_name, .transform = il_soundex)
#'
#' # Per-column substring blocking
#' block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
block_on <- function(..., .where = NULL, .transform = NULL, .explode = NULL) {
  col_exprs <- rlang::enquos(...)
  if (length(col_exprs) == 0L && is.null(.where)) {
    cli::cli_abort('{.fn block_on} requires at least one column or a {.arg .where} condition.')
  }
  validate_transform_arg(.transform)
  if (!is.null(.explode) && !is.character(.explode)) {
    cli::cli_abort(
      '{.arg .explode} must be a character vector or {.code NULL}, not {.obj_type_friendly {(.explode)}}.',
      class = 'il_error_type'
    )
  }
  parsed <- parse_blocking_cols(col_exprs)
  transform <- merge_blocking_transforms(parsed$per_col_tfs, .transform, parsed$columns)
  structure(
    list(
      columns = parsed$columns, where = .where, transform = transform,
      explode = .explode
    ),
    class = 'il_blocking_rule'
  )
}

# Parse a list of quosures into column names and per-column transforms.
# Bare symbols -> column name, no transform.
# col ~ tf formulas -> column name from LHS, transform from evaluated RHS.
# Returns list(columns = chr, per_col_tfs = list).
parse_blocking_cols <- function(col_exprs) {
  columns <- character(length(col_exprs))
  per_col_tfs <- list()

  for (i in seq_along(col_exprs)) {
    expr <- rlang::quo_get_expr(col_exprs[[i]])
    env <- rlang::quo_get_env(col_exprs[[i]])

    if (rlang::is_formula(expr)) {
      lhs <- rlang::f_lhs(expr)
      if (is.null(lhs) || !rlang::is_symbol(lhs)) {
        cli::cli_abort(
          'Left-hand side of a {.code ~} formula must be a bare column name.',
          class = 'il_error_type'
        )
      }
      col <- as.character(lhs)
      tf <- eval(rlang::f_rhs(expr), envir = env)
      if (!is.function(tf)) {
        cli::cli_abort(
          'Right-hand side of {.code {col} ~ ...} must evaluate to a transform function.',
          class = 'il_error_type'
        )
      }
      columns[i] <- col
      per_col_tfs[[col]] <- tf
    } else if (rlang::is_symbol(expr)) {
      columns[i] <- as.character(expr)
    } else {
      columns[i] <- deparse(expr)
    }
  }

  list(columns = columns, per_col_tfs = per_col_tfs)
}

# Combine formula-extracted per-column transforms with the .transform argument.
# Formula transforms take precedence. Returns NULL, a single function, or a
# named list depending on what was provided.
merge_blocking_transforms <- function(per_col_tfs, dot_transform, columns) {
  if (length(per_col_tfs) == 0L) {
    return(dot_transform)
  }
  if (is.null(dot_transform)) {
    return(per_col_tfs)
  }
  # Merge: build a named list, formula transforms take precedence
  if (is.function(dot_transform)) {
    combined <- stats::setNames(
      rep(list(dot_transform), length(columns)),
      columns
    )
  } else {
    combined <- dot_transform
  }
  for (nm in names(per_col_tfs)) {
    combined[[nm]] <- per_col_tfs[[nm]]
  }
  combined
}
