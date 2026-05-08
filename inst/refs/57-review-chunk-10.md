# Chunk 10 review notes

Chunk 10 covers the package's public narrative and end-to-end examples:

- integration-style tests, especially `tests/testthat/test-pipeline-integration.R`
- neighboring end-to-end tests that actually carry part of the same surface:
  `test-link-and-dedupe.R`, `test-stage6-plan.R`, `test-il_phonetic.R`,
  `test-il_transform.R`, `test-explode-blocking.R`
- `README.Rmd`
- `_pkgdown.yml`
- `vignettes/`

This note is now a **post-fix first review**. The initial risks have been
checked against the implementation and docs. Some were real documentation
problems and are now fixed; others turned out to be review priorities rather
than actual errors.

## Risk disposition after follow-up

1. **Not a doc bug: the integration surface really is distributed across more
   than one test file.**

   This was accurate as a review note, not an error. `test-pipeline-integration.R`
   still only covers a narrow dedupe/clustering path, while `link_and_dedupe`,
   backend compatibility, transforms, phonetic blocking, and explode blocking
   are validated in neighboring end-to-end tests.

   No package change was needed here; the practical takeaway is still to review
   the docs and neighboring tests together rather than treating
   `test-pipeline-integration.R` as the whole integration surface.

2. **Mostly not an issue: the baseline public story is coherent, and the main
   weight terminology was already correct.**

   I rechecked `README.Rmd`, `vignettes/irelink.Rmd`, and
   `vignettes/from_splink.Rmd` against the scoring code. The core terminology is
   already consistent:

   - `predict(threshold = ...)` filters on posterior match probability
   - `match_weight` is evidence-only
   - `total_match_weight` is prior-inclusive

   The one real neighboring issue was in the Splink translation example, not in
   the baseline story itself; see item 5 below.

3. **Not a bug by itself: the highest-yield review targets were indeed the
   advanced and remote-data vignettes.**

   That was a prioritization note, not a defect claim. After checking them, the
   actual problems were concentrated in:

   - `vignettes/transactions.Rmd`
   - `vignettes/advanced.Rmd`
   - `vignettes/from_splink.Rmd`

4. **Issue fixed: `vignettes/transactions.Rmd` was documenting an internal state
   mutation as if it were public API.**

   This was a real documentation issue. The vignette set the prior with:

   - `model$params$prior <- 1 / nrow(df_origin)`

   Even though the package exports `il_prior_prevalence()` for exactly this kind
   of user-facing prior setup.

   **Fix:** the vignette now uses:

   - `model <- il_prior_prevalence(model, 1 / nrow(df_origin))`

   I also added prose clarifying that this is the exported helper to use for the
   one-to-one transactions benchmark.

5. **Issue fixed: backend-specific behavior needed clearer wording, and one
   Splink-translation example was genuinely mismatched.**

   There were two separate findings here.

   **A. `transactions.Rmd` was underspecified about backend scope.**

   The vignette already opened a DuckDB connection, but it did not say clearly
   enough that the `.where` blocking rules use raw DuckDB SQL helpers such as
   `strftime()` and `yearweek()`.

   **Fix:** added explicit prose that the workflow assumes DuckDB specifically
   because those blocking rules are written in DuckDB-flavored SQL.

   **B. `from_splink.Rmd` compared unlike threshold types in the side-by-side
   prediction example.**

   The Splink example used `threshold_match_weight=0.5`, while the `irelink`
   example used `threshold = 0.5` (posterior probability). Those are not the
   same contract.

   **Fix:** changed the Splink example to use
   `threshold_match_probability=0.5`, matching the `irelink`
   `predict(model, threshold = 0.5)` example. The note below the example now
   says explicitly that probability thresholds are portable while match-weight
   thresholds require translation.

   **Related clarification:** the `find_matches_to_new_records()` / 
   `il_find_matches()` examples still use different threshold types because the
   two APIs expose different threshold contracts there. I kept the examples but
   added an explicit warning that this threshold translation needs the same
   caution.

6. **Issue fixed: the advanced vignette now states the lazy-prediction backend
   requirement explicitly.**

   This was a documentation clarity issue, not an implementation bug. The code
   already supports `predict(collect = FALSE)` only on DuckDB and PostgreSQL,
   and the implementation of `autoplot()` / `il_waterfall()` on
   `il_compared_lazy` objects is correct.

   **Fix:** `vignettes/advanced.Rmd` now says up front that the lazy path
   requires DuckDB or PostgreSQL and that the vignette is using DuckDB.

   **Not an issue after verification:** the claim that `autoplot()` and
   `il_waterfall()` collect automatically when needed is true:

   - `autoplot.il_compared_lazy()` collects before dispatching
   - `il_waterfall()` calls `ensure_collected()`

7. **Issue fixed: `link_and_dedupe` was under-documented in the user-facing
   narrative.**

   This was not a code bug, but it was a real documentation gap. The package
   supports `link_type = "link_and_dedupe"` in the exported API and has
   end-to-end test coverage, but the narrative docs barely mentioned it.

   **Fix:** added a short note in `vignettes/from_splink.Rmd` that `irelink`
   supports `link_type = "link_and_dedupe"` for two-table jobs with duplicates
   both within and across the input tables.

8. **Issue fixed: the record-linkage vignette now states the blocking/evaluation
   consequence more explicitly.**

   This was a smaller clarity issue. `vignettes/deduplicate-50k.Rmd` already
   explained that when labels enumerate all true matches, blocking-missed true
   pairs become false negatives. `vignettes/record-linkage.Rmd` was using that
   same evaluation contract but did not say it explicitly.

   **Fix:** added one sentence clarifying that because the constructed `labels`
   include all true cross-table matches, any true match missed by blocking is
   counted as a false negative in the evaluation curves.

## Efficient review order now

1. **Start with the baseline story.**

   Read:

   - `README.Rmd`
   - `vignettes/irelink.Rmd`
   - `tests/testthat/test-pipeline-integration.R`

   This surface now looks lower risk. It is mainly a coherence check, not a
   likely source of remaining doc errors.

2. **Then read the fixed high-risk docs together.**

   Read:

   - `vignettes/transactions.Rmd`
   - `vignettes/advanced.Rmd`
   - `vignettes/from_splink.Rmd`

   These were the places where the real documentation issues were found and
   fixed:

   - exported helper versus internal mutation
   - backend-specific wording
   - threshold-type mismatch
   - under-documented `link_and_dedupe`

3. **Then review evaluation narrative consistency.**

   Read:

   - `vignettes/deduplicate-50k.Rmd`
   - `vignettes/record-linkage.Rmd`

   Focus on whether the blocking / false-negative story now reads clearly and
   consistently across both.

4. **Use neighboring tests as contract checks, not just smoke tests.**

   Best supporting reads:

   - `tests/testthat/test-pipeline-integration.R`
   - `tests/testthat/test-link-and-dedupe.R`
   - `tests/testthat/test-stage6-plan.R`
   - `tests/testthat/test-predict.R`
   - `tests/testthat/test-il_waterfall.R`

## Verification

Baseline before the doc fixes:

- full test suite passed
- 1150 passed
- 0 failed

Full test suite was rerun after the documentation fixes as well and still
passed.

## Bottom line

Chunk 10 is now in better shape for human review. The initial scan did identify
real issues, but they were documentation-contract problems rather than broken
runtime behavior:

- a user-facing vignette mutating `model$params$prior` directly
- backend-specific behavior not called out clearly enough
- a Splink translation example mixing match-weight and probability thresholds
- `link_and_dedupe` being under-explained in the narrative docs
- record-linkage evaluation semantics being less explicit than the 50k vignette

Those issues are now fixed, and the remaining Chunk 10 work is mostly a
coherence read rather than a hunt for known doc defects.
