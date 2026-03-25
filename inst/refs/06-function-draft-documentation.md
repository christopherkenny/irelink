# 06 — Draft Roxygen Documentation

> Every exported function in irelink now has roxygen documentation with
> Title, Description, `@param`, `@return`, `@export`, and `@examples`.
> Internal functions use `@noRd` in place of `@export`.

---

## What Was Done

All 43 R source files were updated with roxygen blocks following a
consistent template:

```r
#' Title
#'
#' A brief sentence or two description.
#'
#' @param arg1 Description of first argument.
#' @param arg2 Description of second argument.
#'
#' @return Type of return and a few words.
#' @export
#'
#' @examples
#' \dontrun{
#' my_fn(arg1 = value)
#' }
my_fn <- function(arg1, arg2) {
  cli::cli_warn("Function {.fn my_fn} is not yet implemented.")
  invisible(NULL)
}
```

All function bodies remain as stubs — only the documentation was added.

---

## Counts

| Category | Functions documented | With `@export` | With `@noRd` |
|----------|---------------------|----------------|--------------|
| Specification (`il_spec`, `il_compare`, `il_block_on`, `block_on`) | 7 | 7 | 0 |
| Comparison helpers — similarity (`cl_exact` through `cl_custom`) | 15 | 15 | 0 |
| Comparison helpers — domain (`cl_name`, `cl_dob`, etc.) | 5 | 5 | 0 |
| Comparison helpers — composition (`cl_levels`, `cl_null`, etc.) | 6 | 6 | 0 |
| Model (`il_model`, `print`, `summary`, training verbs) | 8 | 8 | 0 |
| Prediction (`predict.il_model`, `il_compare_records`, `il_find_matches`) | 3 | 3 | 0 |
| Clustering (`il_cluster`, `il_graph_metrics`) | 2 | 2 | 0 |
| Visualization data (`il_weights` through `il_training_history`) | 6 | 6 | 0 |
| Autoplot S3 methods | 2 | 2 | 0 |
| Exploration (`il_completeness` through `il_string_similarity`) | 4 | 4 | 0 |
| Evaluation (`il_accuracy`, `il_errors`) | 2 | 2 | 0 |
| Serialization (`il_save`, `il_load`) | 2 | 2 | 0 |
| Demo (`il_demo`) | 1 | 1 | 0 |
| Unit helpers (`days`, `months`, `years`, `km`, `mi`) | 5 | 5 | 0 |
| Internal class utilities | 6 | 0 | 6 |
| Package-level doc (`_PACKAGE`) | 1 | 0 | 0 |
| **Total** | **75** | **68** | **6** |

`devtools::document()` generates 66 `.Rd` files in `man/` (some topics
share a page, and `@noRd` functions produce none).

---

## Documentation Conventions

### Titles

Each title is an imperative verb phrase consistent with the tidyverse
style (e.g., "Add a Comparison Layer", "Estimate Non-Match Parameters").
Titles for `cl_*` helpers name the comparison method (e.g., "Jaro-Winkler
String Similarity Comparison").

### Descriptions

Descriptions are 1–3 sentences. Where appropriate, they draw analogies
to familiar tidyverse functions (e.g., "`il_model()` is analogous to how
`dplyr::tbl()` binds a connection to a table name"). Cross-references
use `[pkg::fn()]` syntax.

### Parameters

- `spec`, `model`, `pairs`, `.data` are always the first argument,
  enabling pipe usage.
- Tidyselect arguments are tagged with the inline link
  `<[\`tidy-select\`][dplyr::dplyr_tidy_select]>` following dplyr
  convention.
- `...` is documented as either forwarding to S3 generics, accepting
  threshold values, or reserved for future use — never left undocumented.
- `link_type` and `method` use `match.arg()` style defaults with
  `c("option_a", "option_b")`.

### Return Values

Every `@return` tag specifies the class or shape of the return:

| Pattern | Example |
|---------|---------|
| Updated same-class object | "An updated `il_spec`" |
| Tibble with named columns | "A tibble with columns `threshold`, `precision`, ..." |
| Named list of tibbles | "A named list of three tibbles: ..." |
| S3 tagged value | "A tagged numeric with class `il_days`" |
| ggplot object | "A `ggplot` object" |
| Logical | "A single logical value" |

### Examples

All examples are wrapped in `\dontrun{}` because every function body is
currently a stub. Examples are written as-if-working and show realistic
usage including pipe chains.

Representative patterns:

- **Spec building:** pipe chain from `il_spec()` through `il_compare()`
  and `il_block_on()`.
- **Model training:** pipe chain from `il_model()` through
  `il_estimate_*()` verbs.
- **Visualization:** pipe from data-extraction function into ggplot2.
- **Comparison helpers:** single `il_spec() |> il_compare(col, cl_*())`
  call.

### Internal Functions

Six class utility functions in `utils-classes.R` use `@noRd`:

- `new_il_spec()`, `validate_il_spec()`
- `new_il_model()`, `validate_il_model()`
- `new_il_compared()`, `validate_il_compared()`

These still carry full roxygen blocks (title, description, params,
return) for developer reference, but `@noRd` suppresses `.Rd` generation
and export.

---

## Cross-Reference Warnings

`devtools::document()` emits warnings like:

```
✖ cl_date_diff.R:3: @description Could not resolve link to topic "days"
```

These are harmless. They occur because roxygen resolves `[fn()]` links
against the *installed* package namespace, and since irelink has never
been installed, its own topics are not yet findable. The warnings
disappear once the package is installed or once these stubs gain real
implementations.

---

## Files Modified

Every file in `R/` was updated. No new files were created — the file
structure from `05-file-function-structure.md` is unchanged.
