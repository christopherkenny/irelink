#' Create an Empty Linkage Specification
#'
#' Initialises a blank `il_spec` object onto which comparison layers and
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
      cols <- paste(rules[[i]]$columns, collapse = ', ')
      cat(sprintf('    %d. %s\n', i, cols))
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
