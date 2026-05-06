#' Create an Empty Linkage Specification
#'
#' Initializes a blank `il_spec` object onto which comparison layers and
#' blocking rules are added with [il_compare()] and [il_block_on()].
#' Analogous to [ggplot2::ggplot()] creating an empty canvas.
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
      has_where <- !is.null(rule$where) && !is.na(rule$where) && nzchar(rule$where)
      has_tf <- !is.null(rule$transform)
      col_labels <- if (has_tf && is.list(rule$transform)) {
        vapply(rule$columns, function(col) {
          tf <- rule$transform[[col]]
          if (!is.null(tf)) {
            nm <- transform_to_name(tf)
            if (!is.null(nm)) paste0(col, ' [', nm, ']') else col
          } else {
            col
          }
        }, character(1))
      } else {
        rule$columns
      }
      tf_label <- if (has_tf && !is.list(rule$transform)) {
        nm <- transform_to_name(rule$transform)
        if (!is.null(nm)) paste0(' [', nm, ']') else ''
      } else {
        ''
      }
      rule_label <- if (has_cols && has_where) {
        paste0(
          paste(col_labels, collapse = ', '),
          tf_label,
          ' + WHERE ',
          rule$where
        )
      } else if (has_cols) {
        paste0(paste(col_labels, collapse = ', '), tf_label)
      } else if (has_where) {
        paste0('WHERE ', rule$where)
      } else {
        '(empty rule)'
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
