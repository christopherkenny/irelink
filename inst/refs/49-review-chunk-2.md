# Chunk 2 review notes

Chunk 2 covers comparison-level semantics: all `cl_*()` constructors,
shared constructor validation helpers, unit helpers, R-side gamma
calculation, and SQL gamma generation.

Main files:

- `R/cl_array_intersect.R`
- `R/cl_columns_reversed.R`
- `R/cl_cosine.R`
- `R/cl_custom.R`
- `R/cl_date_diff.R`
- `R/cl_distance_km.R`
- `R/cl_domain.R`
- `R/cl_exact.R`
- `R/cl_jaccard.R`
- `R/cl_jaro_winkler.R`
- `R/cl_levels.R`
- `R/cl_levenshtein.R`
- `R/cl_numeric_diff.R`
- `R/cl_time_diff.R`
- `R/utils-comparison-helpers.R`
- `R/utils-unit-helpers.R`

Important downstream files to inspect while reviewing this chunk:

- `R/utils-classes.R`, especially `new_comparison_level()` and
  `n_gamma_levels()`
- `R/utils-sql.R`, especially `sql_gamma_case()` and
  `sql_sublevel_condition()`
- `R/utils-em.R`, especially `compute_gamma()` and
  `compute_gamma_matrix()`

Nearby tests:

- `tests/testthat/test-cl-similarity.R`
- `tests/testthat/test-cl-levels.R`
- `tests/testthat/test-cl-domain.R`
- `tests/testthat/test-cl-time-diff.R`
- `tests/testthat/test-cl_columns_reversed.R`
- `tests/testthat/test-unit-helpers.R`
- `tests/testthat/test-sql-generate.R`
- `tests/testthat/test-null-gamma.R`
- `tests/testthat/test-r-specific.R`

## Risk disposition

1. Confirmed issue: several exported comparison constructors had object tests
   but incomplete active scoring support.

   `sql_gamma_case()` is the main SQL path used by EM, prediction, comparison
   records, and evaluation. Top-level `cl_jaccard()`, `cl_cosine()`,
   `cl_distance_km()`, `cl_array_intersect()`, `cl_array_subset()`, and
   `cl_custom()` were not handled there and could fall through to exact-match
   SQL. The R fallback path also lacked `cl_distance_km()` and
   `cl_array_intersect()` support.

   Fix: `R/utils-sql.R` now emits active gamma SQL for those top-level methods.
   `R/utils-em.R` now computes R fallback gamma for `cl_distance_km()` and
   `cl_array_intersect()`. `cl_custom()` now explicitly errors in the R
   fallback instead of silently behaving like exact equality, because its
   contract is raw SQL. Tests in `test-cl-similarity.R` cover the new active
   SQL/R paths.

2. Confirmed issue: `cl_distance_km()` documentation showed
   `il_compare(c(lat, lon), cl_distance_km(...))`, but `il_compare()` normally
   expands `c()` into one comparison per column.

   Fix: `il_compare()` now special-cases `cl_distance_km()` and stores exactly
   two concrete selected columns as one comparison. Shared comparison naming
   helpers in `R/utils-data.R` produce stable names such as `lat_lon`, and
   active gamma paths use those names for gamma columns. Tests cover the stored
   shape, R gamma, and SQL gamma generation.

3. Confirmed issue: boolean composition was structural only in important paths.

   `cl_and()`, `cl_or()`, and `cl_not()` created comparison-level objects, but
   `sql_sublevel_condition()` and `compute_gamma()` did not evaluate them.
   Inside `cl_levels()`, these could fall back to exact matching semantics.

   Fix: `R/utils-sql.R` now recursively emits SQL conditions for `and`, `or`,
   and `not` sublevels. `R/utils-em.R` now evaluates them in the R fallback.
   Tests in `test-cl-levels.R` cover both R-side gamma and SQL condition
   generation.

4. Confirmed issue: threshold ordering and validation were inconsistent.

   Similarity helpers already validate `[0, 1]` and reorder descending.
   Distance helpers now warn and reorder ascending. Date/time/geographic
   unit-based helpers now reject negative bare numerics and reorder by converted
   day/second/kilometre values. `cl_array_intersect()` now validates thresholds
   separately and reorders descending because larger intersections are stricter.

   Tests cover negative bare numerics for date/time/distance and active
   intersection semantics.

5. Confirmed issue: `cl_literal()` did not escape single quotes and generated
   `= NULL` for missing values.

   Fix: `cl_literal()` now requires a scalar value, escapes single quotes in
   character literals, and emits `IS NULL` for missing literals. Tests cover
   quoted strings and missing values.

6. Reviewed but not changed: null-level semantics use `-1` gamma codes.

   This appears intentional and already has coverage in `test-null-gamma.R` and
   the full suite. No code change was made in this pass. Human review should
   still decide whether this should be documented more explicitly as an
   invariant because it sits outside the ordinary `0..K` gamma range.

7. Reviewed and adjusted test strategy: active gamma tests should target
   `sql_gamma_case()` and `compute_gamma()`.

   `sql_for_comparison_level()` is still present and tested, but the new tests
   intentionally exercise the active gamma paths so constructor-shape tests
   cannot hide scoring regressions.

## Review order

1. Start with the shared object contract in `R/utils-classes.R`.
   Confirm which fields every level may have: `method`, `thresholds`, `units`,
   `levels`, `children`, `child`, `sql_expr`, `term_frequency`,
   `is_null_level`, and `is_else_level`.

2. Build a comparison-method coverage matrix.
   Rows should be every exported `cl_*()` helper. Columns should be:
   constructor validation, `n_gamma_levels()`, `compute_gamma()` support,
   `sql_gamma_case()` support, `sql_sublevel_condition()` support,
   tests covering object shape, tests covering R gamma, tests covering SQL
   gamma, and end-to-end model tests.

3. Review primitive constructors first:
   `cl_exact()`, `cl_jaro_winkler()`, `cl_jaro()`, `cl_levenshtein()`,
   `cl_damerau_levenshtein()`, `cl_jaccard()`, `cl_cosine()`,
   `cl_numeric_diff()`, `cl_pct_diff()`, `cl_date_diff()`,
   `cl_time_diff()`, `cl_distance_km()`, `cl_array_intersect()`,
   `cl_array_min_distance()`, `cl_array_subset()`, and `cl_custom()`.

4. Review structural levels next:
   `cl_null()`, `cl_else()`, `cl_levels()`, `cl_and()`, `cl_or()`,
   `cl_not()`, `cl_literal()`, and `cl_columns_reversed()`.
   Focus on whether nesting works in both SQL and R fallback paths.

5. Review domain bundles last:
   `cl_name()`, `cl_soundex()`, `cl_dob()`, `cl_email()`,
   `cl_forename_surname()`, `cl_first_last_name()`, `cl_postcode()`, and
   `cl_zip_code()`. These are mostly composed from primitives, so their review
   should concentrate on ordering, level count, column references, and whether
   they accidentally use unsupported sublevels.

6. Finish by checking tests against the active paths, not only constructor
   shape. This pass added coverage for top-level `cl_custom()`,
   `cl_jaccard()` / `cl_cosine()` SQL, `cl_distance_km()`,
   `cl_array_intersect()`, nested boolean composition, negative bare
   date/time/distance thresholds, and `cl_literal()` escaping.

## Manual checks to run

- Compare `compute_gamma()` and `sql_gamma_case()` outputs for the same small
  data set for each exported primitive level.
- Verify that `cl_jaccard()` and `cl_cosine()` do not behave as exact matches
  on DuckDB/PostgreSQL paths.
- Verify that `cl_custom('l.score + r.score > 10')` works as a top-level
  comparison in `il_compare()`, not only inside `cl_levels()`.
- Verify that `cl_and()`, `cl_or()`, and `cl_not()` change gamma values inside
  `cl_levels()`.
- Verify that `cl_distance_km(km(1))` expects two columns from
  `il_compare(c(lat, lon), ...)`; current generic gamma paths assume a single
  comparison column, so this needs special attention.
- Verify that `cl_array_intersect(2, 1)` counts shared elements rather than
  falling back to equality.
- Verify that bare negative numerics are rejected by `cl_date_diff()`,
  `cl_time_diff()`, and `cl_distance_km()`.
- Verify that `cl_literal()` handles quotes, `NA`, logical values, and numeric
  values consistently across supported SQL backends.
- Verify that unsorted thresholds either warn/reorder or are documented as
  caller-owned for every method.

## Remaining review focus

1. Decide whether `-1` null gamma levels should be documented as a formal
   invariant. The behavior is covered by tests and was left unchanged.

2. Consider adding a small internal comparison-method coverage table in a
   future maintenance pass so new `cl_*()` helpers must declare their R gamma,
   SQL gamma, sublevel, and test coverage status.

3. Review backend-specific function availability in Chunk 7. This pass made
   Chunk 2 emit the intended SQL; Chunk 7 should still confirm which functions
   are available or registered per backend.

## Verification

Fixed confirmed Chunk 2 issues and verified with:

- Focused comparison tests:
  `test-cl-similarity.R`, `test-cl-levels.R`, `test-cl-domain.R`,
  `test-cl-time-diff.R`, and `test-unit-helpers.R`
- Full suite: `devtools::test()`

Full test result:

- 1041 passed
- 0 failed
- 0 warnings
