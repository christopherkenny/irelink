#' Add a Comparison Layer to a Specification
#'
#' Declares how one or more columns should be compared when scoring record
#' pairs. Each call adds one comparison to the specification.
#'
#' `col` accepts tidyselect expressions: a bare column name, `c(col_a,
#' col_b)`, or helpers such as [tidyselect::starts_with()]. When multiple
#' columns are targeted, each receives its own comparison layer with the
#' same method.
#'
#' @param spec An `il_spec` object (piped in).
#' @param col <[`tidy-select`][dplyr::dplyr_tidy_select]> Column(s) to
#'   compare. Accepts bare names, `c()`, and tidyselect helpers.
#' @param method A comparison helper object created by a `cl_*()` function
#'   such as [cl_exact()] or [cl_jaro_winkler()].
#' @param transform An optional transformation function applied to both
#'   left and right column values *before* comparison. Common choices
#'   include `tolower`, `toupper`, and `trimws`, which are automatically
#'   translated to SQL when a database backend is available. Custom
#'   functions work on the R-side path only.
#' @param tf_adjustment_weight Numeric power to raise the term-frequency
#'   Bayes factor to. A value of `1.0` (the default) applies the full
#'   adjustment. Use `0` to disable it entirely. Only relevant when the
#'   comparison method has `term_frequency = TRUE`.
#' @param tf_minimum_u_value Numeric floor for the term-frequency
#'   denominator. When both TF values are below this threshold, it is
#'   used instead, preventing unrealistically large match weights for
#'   very rare terms. Defaults to `0.0` (no floor).
#' @param ... Reserved for future use.
#'
#' @return An updated copy of `spec`.
#' @export
#'
#' @examples
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_compare(dob, cl_date_diff(days(30), days(365)))
#'
#' # Apply a transform before comparing
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7), transform = tolower)
#'
#' # Scale TF adjustment weight
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, term_frequency = TRUE),
#'     tf_adjustment_weight = 0.5, tf_minimum_u_value = 0.001
#'   )
il_compare <- function(
  spec,
  col,
  method,
  ...,
  transform = NULL,
  tf_adjustment_weight = 1.0,
  tf_minimum_u_value = 0.0
) {
  if (!inherits(spec, 'il_spec')) {
    cli::cli_abort(
      '{.arg spec} must be an {.cls il_spec} object, not {.obj_type_friendly {spec}}.',
      class = 'il_error_type'
    )
  }
  if (!is.null(transform) && !is.function(transform)) {
    cli::cli_abort(
      '{.arg transform} must be a function or {.code NULL}, not {.obj_type_friendly {transform}}.',
      class = 'il_error_type'
    )
  }
  col_expr <- rlang::enquo(col)
  selected <- extract_col_names(col_expr)
  columns <- selected$columns
  if (identical(method$method, 'geo_distance')) {
    if (!is.null(selected$selector) || length(columns) != 2L) {
      cli::cli_abort(
        '{.fn cl_geo_distance} comparisons must select exactly two concrete columns: latitude and longitude.'
      )
    }
    entry <- list(
      columns = columns,
      method = method,
      transform = transform,
      tf_adjustment_weight = tf_adjustment_weight,
      tf_minimum_u_value = tf_minimum_u_value
    )
    spec$comparisons <- c(spec$comparisons, list(entry))
    return(spec)
  }
  for (column in columns) {
    entry <- list(
      columns = column,
      method = method,
      transform = transform,
      tf_adjustment_weight = tf_adjustment_weight,
      tf_minimum_u_value = tf_minimum_u_value
    )
    if (!is.null(selected$selector)) {
      entry$selector <- selected$selector
      entry$deferred_select <- TRUE
    }
    spec$comparisons <- c(spec$comparisons, list(entry))
  }
  spec
}

# Extract column names from a quosure. Handles bare names, c(), and
# tidyselect helpers (which are stored as deferred expressions).
extract_col_names <- function(quo) {
  expr <- rlang::quo_get_expr(quo)
  if (rlang::is_symbol(expr)) {
    return(list(columns = as.character(expr), selector = NULL))
  }
  if (rlang::is_call(expr, 'c')) {
    args <- as.list(expr)[-1]
    simple <- vapply(args, rlang::is_symbol, logical(1))
    if (all(simple)) {
      return(list(
        columns = vapply(args, as.character, character(1)),
        selector = NULL
      ))
    }
    return(list(
      columns = paste(deparse(expr), collapse = ''),
      selector = quo
    ))
  }
  list(
    columns = paste(deparse(expr), collapse = ''),
    selector = quo
  )
}

# Resolve data-dependent tidyselect comparisons once model columns are known.
# Bare-name comparisons are already concrete and pass through unchanged.
resolve_spec_selectors <- function(spec, columns, column_classes = NULL) {
  if (
    !any(vapply(
      spec$comparisons,
      function(comp) {
        isTRUE(comp$deferred_select) && !is.null(comp$selector)
      },
      logical(1)
    ))
  ) {
    return(spec)
  }

  data_proxy <- make_tidyselect_proxy(columns, column_classes)
  resolved <- list()
  for (comp in spec$comparisons) {
    if (!isTRUE(comp$deferred_select) || is.null(comp$selector)) {
      resolved <- c(resolved, list(comp))
      next
    }

    selector <- comp$selector
    selected <- tidyselect::eval_select(
      rlang::quo_get_expr(selector),
      data = data_proxy,
      env = rlang::quo_get_env(selector)
    )
    if (length(selected) == 0L) {
      cli::cli_abort(
        'Tidyselect expression {.code {comp$columns}} did not match any columns.'
      )
    }

    for (column in names(selected)) {
      new_comp <- comp
      new_comp$columns <- column
      new_comp$selector <- NULL
      new_comp$deferred_select <- NULL
      resolved <- c(resolved, list(new_comp))
    }
  }
  spec$comparisons <- resolved
  spec
}

make_tidyselect_proxy <- function(columns, column_classes = NULL) {
  if (is.null(column_classes)) {
    column_classes <- stats::setNames(
      rep(NA_character_, length(columns)),
      columns
    )
  }
  proxy <- lapply(columns, function(col) {
    cls <- column_classes[[col]] %||% NA_character_
    if (is.na(cls)) {
      return(logical())
    }
    switch(
      cls,
      character = character(),
      factor = factor(),
      integer = integer(),
      numeric = numeric(),
      double = numeric(),
      logical = logical(),
      Date = as.Date(character()),
      POSIXct = as.POSIXct(character()),
      POSIXlt = as.POSIXlt(character()),
      logical()
    )
  })
  stats::setNames(proxy, columns)
}

infer_column_classes <- function(df) {
  stats::setNames(vapply(df, function(x) class(x)[1], character(1)), names(df))
}

infer_registered_column_classes <- function(con, tbl_name) {
  out <- try(
    DBI::dbGetQuery(con, glue::glue('SELECT * FROM {tbl_name} WHERE 1 = 0')),
    silent = TRUE
  )
  if (inherits(out, 'try-error')) {
    return(NULL)
  }
  infer_column_classes(out)
}
