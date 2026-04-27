# 41 docs review

Reviewed every documented function topic and updated the docs where the Rd text no longer matched the code.

## Edited documentation

- `il_accuracy()`: added `fn_blocking_miss` to the documented return columns.
- `il_compare_records()`: removed the undocumented promise of match weight and match probability from the return value.
- `il_count_pairs()`: documented the actual `n_pairs` column name and the fact that `cumulative_pairs` and `pct_of_cartesian` are only present when blocking rules are supplied.
- `il_errors()`: corrected the documented return columns to `unique_id_l`, `unique_id_r`, and `match_probability`.
- `il_string_similarity()`: updated the return columns to match the implementation (`cosine` instead of `damerau_levenshtein`, and the current column set/order).
- `il_weights()`: corrected the return column name from `level` to `gamma_level`.
- `il_parameters()`: corrected the documented return shape to match the code: independent models return `comparison`, `gamma_level`, `m`, and `u`; dependency-aware models return the fitted training-pattern table.
- `il_training_history()`: corrected the return column name from `level` to `gamma_level`.
- `cl_name()`: removed the stale reference to Jaro levels; the implementation uses Jaro-Winkler thresholds only.
- `days()`, `months()`, `years()`, `hours()`, `minutes()`, `seconds()`, `km()`, and `mi()`: changed `n` from "positive" to "non-negative" to match validation.

## Regenerated files

- Re-ran roxygen documentation generation so the affected `.Rd` files in `man/` match the updated source docs.
