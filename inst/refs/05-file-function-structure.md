# 05 — File and Function Structure

> Maps every planned irelink export to its R source file.
> See `04-irelink-core-interface.md` for full interface design and examples.

---

## Overview

43 source files in `R/` define 67 exports (60 regular functions, 4 S3
methods, 3 type-check helpers) plus 6 internal class utilities. Every
exported function is a stub that emits a `cli::cli_warn()` "not yet
implemented" message and returns `invisible(NULL)`.

The file-naming convention mirrors the function names. Prefixes (`il_`,
`cl_`) are kept because they provide natural alphabetical grouping:
comparison-level helpers sort together under `cl_*`, core verbs sort
together under `il_*`, and utility files sit at the bottom under
`utils-*`.

---

## File Inventory

### Specification Layer (3 files, 5 exports)

| File | Functions | Visibility |
|------|-----------|------------|
| `il_spec.R` | `il_spec()`, `print.il_spec()`, `is_il_spec()` | exported |
| `il_compare.R` | `il_compare(spec, col, method, ...)` | exported |
| `il_block_on.R` | `il_block_on(spec, ..., .where)`, `block_on(...)` | exported |

`il_spec()` creates an empty specification object. `il_compare()` and
`il_block_on()` are the two main verbs that accumulate layers onto a
spec, following the pure-pipe pattern (§1 / §3 of the interface doc).
`block_on()` (no `il_` prefix) creates training-time blocking rules for
the estimation verbs.

### Comparison Helpers — Similarity (10 files, 13 exports)

| File | Functions |
|------|-----------|
| `cl_exact.R` | `cl_exact(term_frequency)` |
| `cl_jaro_winkler.R` | `cl_jaro_winkler(...)`, `cl_jaro(...)` |
| `cl_levenshtein.R` | `cl_levenshtein(...)`, `cl_damerau_levenshtein(...)` |
| `cl_jaccard.R` | `cl_jaccard(...)` |
| `cl_cosine.R` | `cl_cosine(...)` |
| `cl_date_diff.R` | `cl_date_diff(...)` |
| `cl_distance_km.R` | `cl_distance_km(...)` |
| `cl_numeric_diff.R` | `cl_numeric_diff(...)`, `cl_pct_diff(...)` |
| `cl_array_intersect.R` | `cl_array_intersect(...)` |
| `cl_custom.R` | `cl_custom(sql_expr, ...)` |

Closely related functions are co-located (Jaro/Jaro-Winkler,
Levenshtein/Damerau-Levenshtein, numeric-diff/pct-diff) since they share
the same internal implementation pattern. Each function takes unnamed
threshold arguments ordered from strictest to most lenient (§4.1).

### Comparison Helpers — Domain Bundles (1 file, 5 exports)

| File | Functions |
|------|-----------|
| `cl_domain.R` | `cl_name()`, `cl_dob()`, `cl_email()`, `cl_forename_surname()`, `cl_postcode()` |

Pre-built multi-column comparisons that encode domain knowledge. These
are thin wrappers around the similarity helpers (§4.2).

### Comparison Helpers — Composition (1 file, 6 exports)

| File | Functions |
|------|-----------|
| `cl_levels.R` | `cl_levels(...)`, `cl_null()`, `cl_else()`, `cl_and(...)`, `cl_or(...)`, `cl_not(x)` |

Level-composition operators for building custom comparison structures
from scratch (§4.4).

### Model Layer (5 files, 8 exports)

| File | Functions |
|------|-----------|
| `il_model.R` | `il_model(.data, ..., spec, con, link_type)`, `print.il_model()`, `summary.il_model()`, `is_il_model()` |
| `il_estimate_prior.R` | `il_estimate_prior(model, ..., recall)` |
| `il_estimate_u.R` | `il_estimate_u(model, max_pairs)` |
| `il_estimate_em.R` | `il_estimate_em(model, blocking, ...)` |
| `il_estimate_m_from_labels.R` | `il_estimate_m_from_labels(model, labels)` |

`il_model()` binds data + spec + DBI connection. The four `il_estimate_*`
verbs are pipe-friendly training steps, each taking a model and returning
an updated model (§5).

### Prediction (3 files, 3 exports)

| File | Functions |
|------|-----------|
| `predict.R` | `predict.il_model(object, threshold, type, ...)` |
| `il_compare_records.R` | `il_compare_records(record_a, record_b, spec, con)` |
| `il_find_matches.R` | `il_find_matches(model, new_records, threshold)` |

`predict()` is an S3 method — same generic users call on `lm` or `glm`
objects. Returns an `il_compared` tibble (§6).

### Clustering (2 files, 2 exports)

| File | Functions |
|------|-----------|
| `il_cluster.R` | `il_cluster(pairs, threshold, method)` |
| `il_graph_metrics.R` | `il_graph_metrics(pairs, clusters)` |

Clustering groups scored pairs into entities. `il_graph_metrics()`
returns node-, edge-, and cluster-level tibbles (§7).

### Visualization Data (7 files, 8 exports)

| File | Functions |
|------|-----------|
| `il_weights.R` | `il_weights(model)` |
| `il_parameters.R` | `il_parameters(model)` |
| `il_waterfall.R` | `il_waterfall(pairs, which)` |
| `il_roc.R` | `il_roc(model, labels)` |
| `il_precision_recall.R` | `il_precision_recall(model, labels)` |
| `il_training_history.R` | `il_training_history(model)` |
| `autoplot.R` | `autoplot.il_model(object, ...)`, `autoplot.il_compared(object, which, ...)` |

Each data-extraction function returns a tidy tibble ready for ggplot2.
The `autoplot()` S3 methods provide convenience plots (§8).

### Exploration (4 files, 4 exports)

| File | Functions |
|------|-----------|
| `il_completeness.R` | `il_completeness(..., con)` |
| `il_profile.R` | `il_profile(.data, ..., con)` |
| `il_count_pairs.R` | `il_count_pairs(.data, ..., con, link_type)` |
| `il_string_similarity.R` | `il_string_similarity(a, b)` |

Pre-model diagnostic functions that return tibbles (§9).

### Evaluation (2 files, 2 exports)

| File | Functions |
|------|-----------|
| `il_accuracy.R` | `il_accuracy(model, labels)` |
| `il_errors.R` | `il_errors(model, labels, threshold)` |

Post-prediction quality assessment functions (§10).

### Serialization and Demo (2 files, 3 exports)

| File | Functions |
|------|-----------|
| `il_save.R` | `il_save(model, path)`, `il_load(path)` |
| `il_demo.R` | `il_demo(name)` |

### Utility Files (2 files, 5 exports + 6 internal)

| File | Functions | Visibility |
|------|-----------|------------|
| `utils-unit-helpers.R` | `days(n)`, `months(n)`, `years(n)`, `km(n)`, `mi(n)` | exported |
| `utils-classes.R` | `new_il_spec()`, `validate_il_spec()`, `new_il_model()`, `validate_il_model()`, `new_il_compared()`, `validate_il_compared()` | internal |

Unit helpers are tagged-value constructors inspired by gt's `px()` and
`pct()`. The class utilities are internal constructors and validators for
the three S3 classes (`il_spec`, `il_model`, `il_compared`).

**Note:** `days()`, `months()`, and `years()` share names with lubridate
exports. This is a known collision; see the comment in
`utils-unit-helpers.R`.

### Package Documentation (1 file, 0 exports)

| File | Purpose |
|------|---------|
| `irelink-package.R` | Standard `_PACKAGE` sentinel for roxygen2 |

---

## Argument Ordering Conventions

All exported functions follow the "data first" principle (Design
Principle 1 in the interface doc):

1. **Primary object** — the thing being transformed (`spec`, `model`,
   `pairs`, `.data`)
2. **What to do** — column targets, methods, blocking rules
3. **Named options** — thresholds, types, flags
4. **`...`** — reserved for future extension or forwarded to S3 generics

This ensures every function is pipe-friendly with `|>`.

---

## Totals

| Category | Files | Exports |
|----------|-------|---------|
| Specification | 3 | 5 |
| Comparison (similarity) | 10 | 13 |
| Comparison (domain) | 1 | 5 |
| Comparison (composition) | 1 | 6 |
| Model | 5 | 8 |
| Prediction | 3 | 3 |
| Clustering | 2 | 2 |
| Visualization | 7 | 8 |
| Exploration | 4 | 4 |
| Evaluation | 2 | 2 |
| Serialization / demo | 2 | 3 |
| Utilities | 2 | 5 (+6 internal) |
| Package doc | 1 | 0 |
| **Total** | **43** | **64 + 3 S3 methods** |

---

## Dependencies Added

`DESCRIPTION` now lists:

```
Imports:
    cli,
    tibble
```

`cli` is used by every stub for the warning message. `tibble` is used by
the internal class constructors (`new_il_compared()` validates its input
is a tibble).
