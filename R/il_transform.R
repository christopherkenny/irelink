#' Compose Multiple Transforms into a Chain
#'
#' Creates a single transform function that applies multiple transformations
#' in sequence — first function applied first, last function applied last.
#' The result is itself a function that can be passed as the `transform`
#' argument to [il_compare()] or [il_block_on()].
#'
#' On the SQL side, the transforms are nested inside-out:
#' `il_transform(tolower, trimws)` becomes `TRIM(LOWER(col))`.
#'
#' @param ... Two or more functions to compose, in application order.
#'   Each must be a recognised transform (e.g. `tolower`, `toupper`, `trimws`,
#'   [il_soundex], [il_metaphone], [il_dmetaphone]).
#'
#' @return A function of class `il_transform_chain` that applies all
#'   transforms in order. The individual steps are stored in the
#'   `"transforms"` attribute.
#' @export
#'
#' @examples
#' # Lower-case then trim whitespace
#' tf <- il_transform(tolower, trimws)
#' tf("  Hello  ")
#'
#' # Use in a specification
#' spec <- il_spec() |>
#'   il_compare(name, cl_exact(), transform = il_transform(tolower, trimws))
il_transform <- function(...) {
  fns <- list(...)
  if (length(fns) < 2L) {
    cli::cli_abort(
      '{.fn il_transform} requires at least 2 functions.',
      class = 'il_error_type'
    )
  }
  for (i in seq_along(fns)) {
    if (!is.function(fns[[i]])) {
      cli::cli_abort(
        'Argument {i} of {.fn il_transform} must be a function, \\
         not {.obj_type_friendly {fns[[i]]}}.',
        class = 'il_error_type'
      )
    }
  }
  chain_fn <- function(x) {
    for (fn in fns) {
      x <- fn(x)
    }
    x
  }
  attr(chain_fn, 'transforms') <- fns
  class(chain_fn) <- c('il_transform_chain', 'function')
  chain_fn
}

#' @method print il_transform_chain
#' @export
print.il_transform_chain <- function(x, ...) {
  fns <- attr(x, 'transforms')
  names <- vapply(fns, function(f) {
    n <- transform_to_name(f)
    if (is.null(n)) '<custom>' else n
  }, character(1))
  cat('<il_transform_chain>', paste(names, collapse = ' -> '), '\n')
  invisible(x)
}

#' Check whether an object is a transform chain
#' @noRd
is_transform_chain <- function(x) {
  inherits(x, 'il_transform_chain')
}
