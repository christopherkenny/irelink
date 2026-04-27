# 41 docs review

Reviewed every documented function topic and updated the docs where the
Rd text no longer matched the code.

## Edited documentation

- [`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md):
  added `fn_blocking_miss` to the documented return columns.
- [`il_compare_records()`](http://christophertkenny.com/irelink/reference/il_compare_records.md):
  removed the undocumented promise of match weight and match probability
  from the return value.
- [`il_count_pairs()`](http://christophertkenny.com/irelink/reference/il_count_pairs.md):
  documented the actual `n_pairs` column name and the fact that
  `cumulative_pairs` and `pct_of_cartesian` are only present when
  blocking rules are supplied.
- [`il_errors()`](http://christophertkenny.com/irelink/reference/il_errors.md):
  corrected the documented return columns to `unique_id_l`,
  `unique_id_r`, and `match_probability`.
- [`il_string_similarity()`](http://christophertkenny.com/irelink/reference/il_string_similarity.md):
  updated the return columns to match the implementation (`cosine`
  instead of `damerau_levenshtein`, and the current column set/order).
- [`il_weights()`](http://christophertkenny.com/irelink/reference/il_weights.md):
  corrected the return column name from `level` to `gamma_level`.
- [`il_parameters()`](http://christophertkenny.com/irelink/reference/il_parameters.md):
  corrected the documented return shape to match the code: independent
  models return `comparison`, `gamma_level`, `m`, and `u`;
  dependency-aware models return the fitted training-pattern table.
- [`il_training_history()`](http://christophertkenny.com/irelink/reference/il_training_history.md):
  corrected the return column name from `level` to `gamma_level`.
- [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md):
  removed the stale reference to Jaro levels; the implementation uses
  Jaro-Winkler thresholds only.
- [`days()`](http://christophertkenny.com/irelink/reference/days.md),
  [`months()`](http://christophertkenny.com/irelink/reference/months.md),
  [`years()`](http://christophertkenny.com/irelink/reference/years.md),
  [`hours()`](http://christophertkenny.com/irelink/reference/hours.md),
  [`minutes()`](http://christophertkenny.com/irelink/reference/minutes.md),
  [`seconds()`](http://christophertkenny.com/irelink/reference/seconds.md),
  [`km()`](http://christophertkenny.com/irelink/reference/km.md), and
  [`mi()`](http://christophertkenny.com/irelink/reference/mi.md):
  changed `n` from “positive” to “non-negative” to match validation.

## Regenerated files

- Re-ran roxygen documentation generation so the affected `.Rd` files in
  `man/` match the updated source docs.
