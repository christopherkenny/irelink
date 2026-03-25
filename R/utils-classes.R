# S3 class constructors, validators, and type checks.
# These are internal ─ users create objects via il_spec(), il_model(), etc.

new_il_spec <- function(comparisons = list(), blocking_rules = list()) {
  structure(
    list(comparisons = comparisons, blocking_rules = blocking_rules),
    class = "il_spec"
  )
}

validate_il_spec <- function(x) {
  if (!inherits(x, "il_spec")) {
    cli::cli_abort("{.arg spec} must be an {.cls il_spec} object.")
  }
  invisible(x)
}

new_il_model <- function(spec = new_il_spec(), data = list(), con = NULL,
                         link_type = "dedupe", params = list(),
                         trained = FALSE) {
  structure(
    list(
      spec = spec,
      data = data,
      con = con,
      link_type = link_type,
      params = params,
      trained = trained
    ),
    class = "il_model"
  )
}

validate_il_model <- function(x) {
  if (!inherits(x, "il_model")) {
    cli::cli_abort("{.arg model} must be an {.cls il_model} object.")
  }
  invisible(x)
}

new_il_compared <- function(x = tibble::tibble(), model = NULL) {
  if (!inherits(x, "tbl_df")) {
    cli::cli_abort("{.arg x} must be a tibble.")
  }
  structure(x, class = c("il_compared", class(x)), model = model)
}

validate_il_compared <- function(x) {
  if (!inherits(x, "il_compared")) {
    cli::cli_abort("{.arg pairs} must be an {.cls il_compared} object.")
  }
  invisible(x)
}
