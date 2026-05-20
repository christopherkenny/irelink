#' Prepend a class to a tibble
#'
#' Adds a custom S3 class in front of the existing class vector so that
#' methods like `autoplot()` can dispatch on it while preserving the
#' underlying tibble behavior.
#'
#' @param x A tibble.
#' @param cls Character string. The class name to prepend.
#'
#' @return `x` with `cls` prepended to its class vector.
#' @noRd
add_class <- function(x, cls) {
  class(x) <- c(cls, class(x))
  x
}
