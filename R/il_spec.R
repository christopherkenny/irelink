#' Construct an il_spec Object
#'
#' Low-level constructor for the `il_spec` S3 class. Users should call
#' [il_spec()] instead.
#'
#' @param comparisons A list of comparison layers.
#' @param blocking_rules A list of blocking-rule objects.
#'
#' @return An `il_spec` object.
#' @noRd
new_il_spec <- function(comparisons = list(), blocking_rules = list()) {
  structure(
    list(comparisons = comparisons, blocking_rules = blocking_rules),
    class = 'il_spec'
  )
}

#' Validate an il_spec Object
#'
#' Checks that `x` inherits from `il_spec` and aborts with an
#' informative error if not.
#'
#' @param x An object to validate.
#'
#' @return `x`, invisibly.
#' @noRd
validate_il_spec <- function(x) {
  if (!inherits(x, 'il_spec')) {
    cli::cli_abort('{.arg spec} must be an {.cls il_spec} object.')
  }
  if (!is.list(x) || is.null(x$comparisons) || is.null(x$blocking_rules)) {
    cli::cli_abort(
      '{.cls il_spec} must contain {.field comparisons} and {.field blocking_rules}.'
    )
  }
  invisible(x)
}

#' Create an Empty Linkage Specification
#'
#' Initializes a blank `il_spec` object onto which comparison layers and
#' blocking rules are added with [il_compare()] and [il_block_on()].
#'
#' @return An `il_spec` object with no comparisons or blocking rules.
#' @export
#'
#' @examples
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
#'   il_block_on(surname)
il_spec <- function() {
  new_il_spec()
}

#' Print an irelink Specification
#'
#' Displays a human-readable summary of the comparisons and blocking rules
#' stored in an `il_spec` object.
#'
#' @param x An `il_spec` object.
#' @param ... Additional arguments passed to [print()].
#'
#' @return `x`, invisibly.
#' @export
#'
#' @examples
#' spec <- il_spec() |>
#'   il_compare(first_name, cl_exact())
#' print(spec)
print.il_spec <- function(x, ...) {
  cat('Linkage Specification\n')

  comps <- x$comparisons
  if (length(comps) == 0L) {
    cat('  Comparisons: (none)\n')
  } else {
    cat(sprintf('  Comparisons (%d):\n', length(comps)))
    for (comp in comps) {
      cols <- paste(comp$columns, collapse = ', ')
      method <- comp$method$method %||% 'custom'
      cat(sprintf('    %s : %s\n', cols, method))
    }
  }

  rules <- x$blocking_rules
  if (length(rules) == 0L) {
    cat('  Blocking rules: (none)\n')
  } else {
    cat(sprintf('  Blocking rules (%d, OR-ed):\n', length(rules)))
    for (i in seq_along(rules)) {
      rule <- rules[[i]]
      has_cols <- length(rule$columns) > 0L
      has_where <- !is.null(rule$where) &&
        !is.na(rule$where) &&
        nzchar(rule$where)
      has_tf <- !is.null(rule$transform)
      col_labels <- rule$columns
      if (has_tf && is.list(rule$transform)) {
        col_labels <- vapply(
          rule$columns,
          function(col) {
            tf <- rule$transform[[col]]
            if (!is.null(tf)) {
              nm <- transform_to_name(tf)
              if (!is.null(nm)) paste0(col, ' [', nm, ']') else col
            } else {
              col
            }
          },
          character(1)
        )
      }
      tf_label <- ''
      if (has_tf && !is.list(rule$transform)) {
        nm <- transform_to_name(rule$transform)
        if (!is.null(nm)) {
          tf_label <- paste0(' [', nm, ']')
        }
      }
      rule_label <- '(empty rule)'
      if (has_cols && has_where) {
        rule_label <- paste0(
          paste(col_labels, collapse = ', '),
          tf_label,
          ' + WHERE ',
          rule$where
        )
      } else if (has_cols) {
        rule_label <- paste0(paste(col_labels, collapse = ', '), tf_label)
      } else if (has_where) {
        rule_label <- paste0('WHERE ', rule$where)
      }
      cat(sprintf('    %d. %s\n', i, rule_label))
    }
  }

  invisible(x)
}

#' Test if an Object is an irelink Specification
#'
#' Returns `TRUE` if `x` inherits from class `il_spec`.
#'
#' @param x An object to test.
#'
#' @return A single logical value.
#' @export
#'
#' @examples
#' is_il_spec(il_spec())
is_il_spec <- function(x) {
  inherits(x, 'il_spec')
}
