# Chunk 3 review notes

Chunk 3 covers column transforms: transform chains, exported
parameterized transform helpers, and the contract by which transforms are
applied before comparison or blocking SQL is generated.

Main files:

- `R/il_transform.R`
- `R/il_column_transforms.R`

Important neighboring files inspected for this chunk:

- `R/utils-sql.R`, especially `sql_transform_col()`,
  `transform_to_name()`, and `build_blocking_condition()`
- `R/utils-em.R`, especially `compute_gamma_matrix()`
- `R/il_compare.R`, for transform validation/storage
- `R/il_block_on.R`, for formula transforms and per-column blocking
  transforms
- `R/il_save.R`, for Splink JSON export/import behavior

Nearby tests:

- `tests/testthat/test-il_transform.R`
- `tests/testthat/test-column-transforms.R`
- `tests/testthat/test-transform.R`
- `tests/testthat/test-il_block_on.R`
- `tests/testthat/test-il_save.R`

## Risk disposition

1. Confirmed issue: custom R transforms were silently ignored on SQL paths.

   `sql_transform_col()` returned the original column reference when a
   transform function had no SQL translation. On DuckDB/PostgreSQL, active
   gamma generation runs in SQL, so an unknown transform could change scores
   by being dropped without warning.

   Fix: `sql_transform_col()` now raises an `il_error_type` when a non-NULL
   transform cannot be translated to SQL. R fallback behavior still works
   because `compute_gamma_matrix()` applies the transform directly in R.

   Tests added: `test-transform.R` verifies custom transforms error on SQL
   gamma paths.

2. Confirmed issue: parameterized transform SQL did not escape string
   literals.

   `il_regex_extract()`, `il_nullif()`, `il_try_parse_date()`, and
   `il_try_parse_timestamp()` embedded user-provided strings directly in
   single-quoted SQL. Values containing `'` could generate invalid SQL or
   change the intended expression.

   Fix: added `sql_quote_literal()` and routed transform SQL literals through
   it. This covers regex patterns, null-if values, and date/time format
   strings.

   Tests added: `test-column-transforms.R` covers quoted values and regex
   patterns containing single quotes.

3. Confirmed issue: `il_regex_extract(group > 0)` had SQL/R parity drift.

   The constructor accepted capture groups, and SQL generation emitted the
   requested group, but the R closure always returned the whole match.

   Fix: the R implementation now uses `regexpr(..., perl = TRUE)` capture
   metadata to return the requested capture group. Missing inputs,
   non-matches, and patterns without that group return `NA`.

   Tests added: `test-column-transforms.R` covers grouped extraction in R.

4. Confirmed issue: PostgreSQL date/time parsing used R-style format strings
   directly.

   `il_try_parse_date()` and `il_try_parse_timestamp()` accept R
   `strptime`-style formats such as `%Y-%m-%d`, but PostgreSQL `TO_DATE()` and
   `TO_TIMESTAMP()` expect template tokens such as `YYYY-MM-DD`.

   Fix: added `strptime_to_postgres_format()` for the common tokens used by
   these helpers. DuckDB still receives the original `strptime` format.
   DuckDB date parsing now casts `try_strptime()` to `DATE` for the date
   helper.

   Tests added: PostgreSQL SQL generation now asserts translated templates
   such as `YYYY-MM-DD HH24:MI:SS`, not just the function name.

5. Confirmed issue: `il_array_element("last")` was not dialect-aware.

   The previous SQL emitted `col[-1]` for every dialect. That is suitable for
   DuckDB, but PostgreSQL needs array-length indexing for the last element.

   Fix: `il_array_element()` SQL now emits `col[-1]` for DuckDB and
   `col[array_length(col, 1)]` for PostgreSQL. Array-element SQL now errors on
   unsupported dialects.

   Tests added: `test-column-transforms.R` covers DuckDB and PostgreSQL SQL
   generation and unsupported-dialect errors.

6. Confirmed issue: named-list blocking transforms were under-validated.

   `il_block_on()` and `block_on()` accepted named transform lists, but extra
   names were silently ignored and missing selected-column names quietly meant
   no transform for that column.

   Fix: named-list `.transform` values must now match the blocking columns.
   Formula transforms can still fill entries when mixed with a named list, and
   formula transforms continue to take precedence.

   Tests added: `test-il_block_on.R` covers extra names, missing names, and
   formula transforms filling named-list entries.

7. Reviewed and left unchanged: transform chain semantics.

   `il_transform()` applies functions in R order, and `sql_transform_col()`
   nests SQL in the same order. Existing tests cover chains with two and three
   built-in transforms, and a chain containing a parameterized transform.
   Unknown custom transforms inside a chain now fail via the same strict SQL
   translation check described above.

8. Reviewed and left unchanged: JSON save/load transform round-tripping.

   JSON export writes transformed Splink SQL conditions. JSON import rebuilds
   those conditions as `cl_custom()` levels with `transform = NULL`. That is
   intentional because the SQL behavior, not the original R closure, is the
   portable artifact. Existing save/load tests cover transformed comparisons
   and prediction after attach.

## Review order

1. Start with the transform object contracts in `R/il_transform.R` and
   `R/il_column_transforms.R`. Confirm class attributes, stored parameters,
   validation, and R-side behavior for every exported transform.

2. Review SQL generation through `sql_transform_col()` and
   `column_transform_sql()`. The important invariant is now strict: a
   non-NULL transform must either produce SQL or error.

3. Review parity between SQL and R fallback behavior. Focus on
   `compute_gamma_matrix()` for comparisons and `build_blocking_condition()`
   for blocking rules.

4. Review dialect-specific transforms last: PostgreSQL date/time template
   translation and array indexing are intentionally handled in
   `column_transform_sql()`.

5. Finish by checking save/load semantics. Transformed comparisons are exported
   as SQL and imported as custom SQL levels; transform closures themselves are
   not expected to round-trip.

## Manual checks covered

- Unknown custom transform on a DuckDB SQL gamma path now errors instead of
  being silently dropped.
- `il_nullif("O'Reilly")` produces escaped SQL.
- `il_regex_extract("([A-Z]+)([0-9]+)", group = 2)` returns the capture group
  in R.
- PostgreSQL date/time SQL translates `%Y-%m-%d %H:%M:%S` to
  `YYYY-MM-DD HH24:MI:SS`.
- `il_array_element("last")` emits DuckDB and PostgreSQL-specific SQL.
- Named-list `.transform` values with extra or missing column names now error.
- Formula transforms still override/fill per-column blocking transforms.
- Save/load of transformed comparisons still predicts after attach.

## Remaining review focus

1. Decide whether `strptime_to_postgres_format()` should support more
   PostgreSQL/R format tokens before claiming broad PostgreSQL date/time
   format compatibility. The common package examples are now covered.

2. Consider documenting the strict SQL transform policy in user-facing docs:
   built-in transforms are SQL-capable; arbitrary R closures are R-fallback
   only and will error on SQL generation paths.

3. Consider whether imported transformed blocking rules should be documented
   as raw SQL conditions after JSON load, matching the comparison import
   behavior.

## Verification

Focused tests passed for:

- `test-column-transforms.R`
- `test-il_transform.R`
- `test-transform.R`
- `test-il_block_on.R`
- `test-il_save.R`

Full suite also passed after the fixes:

- 1055 passed
- 0 failed
- 0 warnings
