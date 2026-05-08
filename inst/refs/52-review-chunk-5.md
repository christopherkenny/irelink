# Chunk 5 review notes

Chunk 5 covers prediction and scoring after model parameters already exist:
candidate scoring, incremental matching, deterministic fallback, one-pair
comparison, missing-edge scoring, waterfall decomposition, and public weight
summaries.

Main files:

- `R/predict.R`
- `R/il_find_matches.R`
- `R/il_deterministic_link.R`
- `R/il_compare_records.R`
- `R/il_score_missing_edges.R`
- `R/il_waterfall.R`
- `R/il_weights.R`
- `R/utils-scoring.R`

Important neighboring files inspected:

- `R/utils-sql.R`, for SQL scoring, TF adjustments, greedy matching, and
  field joins
- `R/utils-em.R`, for R-side gamma extraction and transforms
- `R/utils-tf.R`, for TF lookup and adjustment parity
- `R/utils-dependency-aware.R`, for pattern scoring and SQL score lookup
- `R/utils-classes.R`, for `il_compared` and lazy collection
- `R/utils-evaluation.R`, for canonical pair keys

Nearby tests:

- `tests/testthat/test-predict.R`
- `tests/testthat/test-include-fields.R`
- `tests/testthat/test-il_waterfall.R`
- `tests/testthat/test-il_weights.R`
- `tests/testthat/test-il_score_missing_edges.R`
- `tests/testthat/test-il_deterministic_link.R`
- `tests/testthat/test-link-and-dedupe.R`
- `tests/testthat/test-r-specific.R`
- `tests/testthat/test-term-frequency.R`
- `tests/testthat/test-dependency-aware-scoring.R`
- `tests/testthat/test-table-lifecycle.R`
- `tests/testthat/test-sql-profile.R`

## Risk disposition

1. Confirmed issue: prediction controls were under-validated.

   `predict.il_model()` validated the model and `greedy`, but not
   `threshold`, `threshold_match_weight`, `collect`, `include_fields`, or
   `profile_sql`. These values affect SQL generation and branching.

   Fix: added shared scalar validators in `utils-scoring.R`; `predict()` now
   validates all public scoring controls before building SQL.

   Tests added: `test-predict.R` covers invalid probability, match-weight,
   and logical controls.

2. Confirmed issue: `predict(type = "weights")` was accepted but ignored.

   The argument was matched but did not alter behavior.

   Fix: `type = "weights"` now returns the same tidy fieldwise weight summary
   as `il_weights(model)`. `type = "pairs"` remains the scored-pair default.

   Tests added: `test-predict.R` verifies the returned columns and equality to
   `il_weights()`.

3. Confirmed issue: prior boundary handling differed between helpers.

   `prior_match_weight()` clamped priors, but `weight_to_probability()` and SQL
   scoring used direct prior odds. Boundary priors could therefore rely on
   fragile `Inf` arithmetic.

   Fix: `weight_to_probability()` now converts through clamped
   `total_match_weight()`, and `build_scored_query()` clamps `safe_prior()`
   before generating SQL odds.

   Tests added: `test-predict.R` covers `prior = 0` and `prior = 1` probability
   conversion.

4. Reviewed and partly fixed: SQL/R prediction shape parity.

   The ordinary non-empty paths were already covered by existing prediction,
   include-fields, TF, dependency-aware, table-lifecycle, and SQL-profile tests.
   Empty SQL-first prediction with a real query preserves the SQL result shape.

   Fix: dependency-aware empty prediction paths now use `empty_scored_pairs()`
   so gamma and TF-adjustment columns are preserved where possible.

5. Confirmed issue: `il_find_matches()` did not validate trained state,
   threshold, or missing columns for non-data-frame inputs.

   The function read trained parameters after only class validation, and only
   padded missing columns when `new_records` was a data frame.

   Fix: `il_find_matches()` now uses the trained-model validator, validates
   `threshold`, computes needed columns from comparison source columns rather
   than comparison names, and errors clearly if registered new-record inputs
   lack required columns.

   Tests added: `test-il_waterfall.R` covers untrained models, invalid
   thresholds, and missing columns in a table-name input.

6. Reviewed and left as documented review focus: `il_find_matches()` matches
   new records against `model$data$tbl_l`.

   This appears to be an API semantics question, not a confirmed bug from the
   current tests: incremental matching is framed as scoring new records against
   the model's existing data. Human review should decide whether link and
   link-and-dedupe models need a broader target-table contract.

7. Confirmed issue: `il_score_missing_edges()` under-validated inputs and
   bypassed shared gamma/TF scoring behavior.

   It assumed cluster and pair columns existed, fetched source records through
   a combined ID list, manually called `compute_gamma()` without transforms,
   and did not apply TF adjustments.

   Fix: it now validates trained state, threshold, `pairs`, and `clusters`;
   builds pair-shaped data separately from left/right source tables; reuses
   `compute_gamma_matrix()` so transforms are honored; applies TF adjustments;
   and returns gamma/TF columns with the scored missing edges.

   Tests added: `test-il_score_missing_edges.R` covers input validation and
   gamma/TF-adjustment output.

8. Confirmed issue: `il_deterministic_link()` exposed unsupported multi-table
   surface.

   The signature accepted `...` and `link_type`, but the implementation only
   performed a single-table self-join.

   Fix: the function now errors clearly unless called as single-table
   `link_type = "dedupe"`. Full multi-table deterministic linking can be a
   future feature rather than silent partial behavior.

   Tests added: `test-il_deterministic_link.R` covers explicit rejection.

9. Confirmed issue: `il_compare_records()` silently used the first row and
   failed late on missing columns.

   Fix: it now requires each input to contain exactly one row and validates
   that all spec comparison columns are present in both record inputs.

   Tests added: `test-il_waterfall.R` covers multi-row and missing-column
   inputs.

10. Confirmed issue: `il_waterfall()` did not validate `which`.

    Out-of-bounds or non-scalar row indices failed unclearly after subsetting.

    Fix: `il_waterfall()` now requires a positive integer row index present in
    `pairs`.

    Tests added: `test-il_waterfall.R` covers invalid and out-of-bounds
    `which`.

11. Confirmed issue: fieldwise weight summaries were unclear for
    dependency-aware models.

    Dependency-aware scores are pattern-level, not field-decomposable in the
    same way as independent m/u parameters.

    Fix: `il_weights()` now errors clearly for dependency-aware models.
    `predict(type = "weights")` therefore inherits the same fieldwise contract.

12. Reviewed and left for Chunk 7: identifier quoting and direct SQL
    interpolation.

    Chunk 5 still has call sites that assume simple registered table/column
    names. This is a database infrastructure concern shared with comparison
    SQL and table registration, so it should be handled in Chunk 7 rather than
    patched piecemeal here.

## Review order

1. Start with `R/utils-scoring.R`.

   Confirm the public scoring contract: evidence-only `match_weight`,
   prior-inclusive `total_match_weight`, clamped prior odds, and posterior
   probability conversion.

2. Review `R/predict.R`.

   Check the now-validated controls, the `type = "weights"` branch, SQL-first
   collect, lazy prediction, R fallback, empty outputs, `threshold_match_weight`,
   `include_fields`, `greedy`, TF columns, and dependency-aware mode.

3. Review `R/il_find_matches.R`.

   Focus on incremental matching semantics, especially whether matching only
   against `model$data$tbl_l` is right for link/link-and-dedupe models.

4. Review `R/il_score_missing_edges.R`.

   Confirm that the new pair-shaped scoring path matches `predict()` for
   transforms, nulls, distance comparisons, TF adjustments, and same-table
   orientation. Two-table cluster semantics still deserve human attention.

5. Review the smaller helpers.

   Check `il_compare_records()` one-row/missing-column validation,
   `il_waterfall()` bounds behavior and dependency-aware rejection,
   `il_weights()` fieldwise-only semantics, and
   `il_deterministic_link()`'s explicit dedupe-only contract.

## Remaining human-review focus

1. Decide and document `il_find_matches()` target-table semantics for
   link/link-and-dedupe models.

2. Decide whether `il_deterministic_link()` should eventually support true
   multi-table deterministic linkage, or whether the public signature/docs
   should be narrowed to dedupe-only.

3. In Chunk 7, review SQL identifier quoting and direct interpolation across
   these scoring callers together with the shared SQL infrastructure.

4. Add an explicit SQLite-vs-DuckDB parity test for a tiny model if the review
   wants backend parity pinned more tightly than the current focused tests.

## Verification

Focused tests passed after fixes:

- `test-predict.R`: 42 passed
- `test-il_waterfall.R`: 19 passed
- `test-il_score_missing_edges.R`: 7 passed
- `test-il_deterministic_link.R`: 5 passed

Broader Chunk 5-adjacent tests also passed:

- `test-include-fields.R`: 14 passed
- `test-term-frequency.R`: 39 passed
- `test-dependency-aware-scoring.R`: 35 passed
- `test-table-lifecycle.R`: 16 passed
- `test-sql-profile.R`: 8 passed
- `test-link-and-dedupe.R`: 28 passed
- `test-r-specific.R`: 28 passed

Full suite also passed after the fixes:

- 1076 passed
- 15 skipped
- 0 failed
- 0 warnings
