# Chunk 1 review notes

Chunk 1 covers the package foundations: specs, models, class constructors,
registered data, comparisons, blocking rules, and link modes.

Main files:

- `R/il_spec.R`
- `R/il_model.R`
- `R/utils-classes.R`
- `R/utils-data.R`
- `R/utils-register.R`
- `R/il_compare.R`
- `R/il_block_on.R`

Nearby tests:

- `tests/testthat/test-il_spec.R`
- `tests/testthat/test-il_compare.R`
- `tests/testthat/test-il_block_on.R`
- `tests/testthat/test-il_model.R`
- `tests/testthat/test-register-data.R`
- `tests/testthat/test-il_attach.R`
- `tests/testthat/test-link-and-dedupe.R`

## Risk disposition

1. Confirmed issue: `il_compare()` advertised tidyselect support, but
   `extract_col_names()` only resolved bare names and simple `c()` calls.
   Helpers like `starts_with()` were stored as strings and failed later during
   model column validation.

   Fix: `il_compare()` now stores data-dependent selectors as deferred
   quosures, and `il_model()` / `il_attach()` resolve them after registering
   the left data and before validating columns. This expands helpers such as
   `starts_with()` into one comparison per matched column. Data-frame inputs
   also preserve column classes so `tidyselect::where()` can resolve against
   the actual input types.

   Tests added: `test-il_compare.R` now verifies `starts_with()` resolves in
   `il_model()` and `where(is.character)` uses data column classes.

2. Confirmed issue: `il_model()` and `il_attach()` validated spec columns
   against the left table only. In `link` and `link_and_dedupe` modes, missing
   right-side columns could fail later as SQL errors.

   Fix: after registering the right table, both functions now validate the
   resolved spec columns against the right-side columns and raise an early,
   targeted error.

   Tests added: `test-il_model.R` and `test-il_attach.R` cover missing
   right-side columns in link mode.

3. Confirmed issue: extra datasets were silently ignored. Both `il_model()` and
   `il_attach()` accepted `...`, but only `extra_inputs[[1]]` was used.

   Fix: both functions now error when more than two datasets are supplied.

   Tests added: `test-il_model.R` and `test-il_attach.R` cover the
   more-than-two-datasets case.

4. Confirmed issue with a narrower scope: existing `unique_id` columns were
   trusted without checking the invariants needed by pair generation. Character
   IDs are valid and already covered elsewhere, so the fix does not restrict
   the ID type. Overlapping IDs across link tables remain allowed because
   source-table identity is tracked separately in the pair machinery.

   Fix: `register_data()` now validates existing or synthesized `unique_id`
   values when an ID column is present: no missing values and no duplicates
   within the registered table. It still allows ID-free diagnostic
   registrations when callers intentionally use `add_unique_id = FALSE`.

   Tests added: `test-register-data.R` covers duplicate and missing
   `unique_id` values.

5. Confirmed issue: `il_block_on()` could add an empty prediction blocking rule
   when called with no columns and no `.where`, while `block_on()` already
   rejected the same shape.

   Fix: `il_block_on()` now requires at least one column or a `.where`
   condition.

   Tests added: `test-il_block_on.R` covers the empty call.

## Review order

1. Start with object shape in `R/utils-classes.R`. Confirm which invariants are
   real versus conventional for `il_spec`, `il_model`, comparison entries, and
   blocking rules.

2. Review spec mutation in `R/il_compare.R` and `R/il_block_on.R`. Focus on
   what is stored in the spec. Defer comparison-level semantics to Chunk 2 and
   transform SQL details to Chunks 3 and 7.

3. Review data ownership and registration in `R/utils-register.R` and
   `R/utils-data.R`. Check that data frame, table-name, and `tbl_lazy` inputs
   satisfy the same contract.

4. Review model lifecycle in `il_model()` and `il_attach()`. Verify table
   metadata, connection ownership, trained parameter preservation, and link-mode
   setup.

5. Finish by mapping each invariant to tests. Use the nearby test files listed
   above and look for tests that only assert "no error" or object class without
   checking the downstream behavior.

## Manual checks covered

- `il_compare(starts_with("addr_"), cl_exact())` followed by `il_model()` on
  data with matching columns: covered in `test-il_compare.R`.
- `link` mode where the right table is missing a spec column.
  Covered in `test-il_model.R` and `test-il_attach.R`.
- Passing three datasets to `il_model(df1, df2, df3, ...)` and `il_attach()`:
  covered in `test-il_model.R` and `test-il_attach.R`.
- Existing `unique_id` with duplicates and `NA`: covered in
  `test-register-data.R`.
- Character `unique_id` remains supported by existing blocked-pairs tests.
- Overlapping `unique_id` values across link tables remain allowed by design
  because pair source identity is tracked separately where needed.
- `il_spec() |> il_block_on()` with no args: covered in `test-il_block_on.R`.

## Verification

Targeted tests passed for:

- `test-il_compare.R`
- `test-il_block_on.R`
- `test-il_model.R`
- `test-register-data.R`
- `test-il_attach.R`
- `test-link-and-dedupe.R`

Full test suite also passed after the fixes:

- 1000 passed
- 15 skipped
- 0 failed
