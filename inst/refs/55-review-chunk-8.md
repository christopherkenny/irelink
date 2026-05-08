# Chunk 8 review notes

Chunk 8 covers both post-model evaluation and pre-model diagnostics:

- `R/il_accuracy.R`
- `R/il_roc.R`
- `R/il_precision_recall.R`
- `R/il_comparator_score.R`
- `R/il_confusion_matrix.R`
- `R/il_cluster_confusion_matrix.R`
- `R/il_completeness.R`
- `R/il_comparison_vectors.R`
- `R/il_unlinkables.R`
- `R/il_largest_blocks.R`
- `R/il_suggest_blocking.R`
- `R/il_errors.R`
- `R/il_profile.R`
- `R/il_string_similarity.R`
- `R/utils-evaluation.R`

This is a **first-pass review**, not a finished audit. The goal here is to
point a human reviewer at the highest-yield reads first.

## Risk disposition after implementation

1. **Issue fixed: fallback evaluation now handles blocking rules correctly.**

   This was a real bug on the SQLite / R fallback path. `score_labeled_pairs()`
   previously fetched only comparison columns, then tried to re-evaluate
   blocking rules in R. That broke when blocking columns were not part of the
   comparison set and also failed to respect blocking transforms and raw SQL
   conditions.

   **Fix:** added a shared `label_blocking_flags()` helper in
   `R/utils-evaluation.R` that uploads the labeled pairs and evaluates the
   model's blocking rules in SQL for all backends. The fallback path now uses
   that helper instead of hand-rolled R equality checks.

   **Related fix:** `il_errors()` now applies the same `found_by_blocking`
   contract as `il_accuracy()` / `il_confusion_matrix()`, so blocking-missed
   true matches are reported as false negatives instead of disappearing.

   **Regression coverage:** `tests/testthat/test-il_accuracy.R` now covers a
   SQLite fallback case where prediction blocking uses `first_name`, the
   comparison uses `surname`, and two true-match pairs are missed by blocking.

2. **Issue fixed: DuckDB comparator scores were scaled down by 100x.**

   This was a real bug. `R/il_comparator_score.R` divided DuckDB's
   `jaro_similarity()` and `jaro_winkler_similarity()` outputs by `100.0`, but
   DuckDB already returns values in `[0, 1]`.

   **Fix:** removed the `/ 100.0` scaling and added identifier quoting for the
   SQL comparator path at the same time.

   **Regression coverage:** `tests/testthat/test-comparator-score.R` now checks
   that DuckDB scores for `"John"` vs `"Jon"` remain above `0.9` and that the
   SQL path works with non-syntactic column names.

3. **Issue fixed: `il_largest_blocks()` now applies blocking transforms.**

   This was a real bug. `R/il_largest_blocks.R` previously grouped on raw column
   values even when the blocking rule specified `.transform`.

   **Fix:** the function now uses the same SQL transform machinery as the rest
   of the package, projecting transformed blocking keys in a subquery and then
   grouping on those transformed values.

   **Regression coverage:** `tests/testthat/test-suggest-blocking.R` now checks
   that `block_on(name, .transform = il_substr(1, 1))` yields `A`/`B` bins
   rather than four singleton raw-name bins.

4. **Issue fixed: `il_unlinkables()` now handles link models correctly.**

   This was a real bug. The function used `n_records_l` as the denominator even
   when predictions came from two tables, which could produce impossible values
   such as `-1`.

   **Fix:** for non-dedupe models, `il_unlinkables()` now measures unlinkability
   over the combined left + right record set and counts left/right records
   separately by prefixing their IDs before taking unique counts. That avoids
   both negative percentages and collisions when the two tables reuse the same
   `unique_id` values.

   **Regression coverage:** `tests/testthat/test-il_roc.R` now includes a
   two-table link case that verifies `pct_unlinkable` stays in `[0, 1]` and is
   `0` at threshold `0` when both records are linked.

5. **Issue fixed: identifier quoting was a real diagnostics-layer bug.**

   This was not just a review note; the risk was real. Several Chunk 8 helpers
   still interpolated raw table and column names directly into SQL:

   - `R/il_comparator_score.R`
   - `R/il_largest_blocks.R`
   - `R/il_suggest_blocking.R`
   - `block_from_labels()` in `R/il_suggest_blocking.R`
   - `R/il_cluster_confusion_matrix.R`

   **Fix:** these paths now use the shared identifier helpers from
   `R/utils-sql.R` (`sql_quote_identifier()`, `sql_identifier_csv()`, and
   related patterns) for table references, selected columns, and label columns.

   **Regression coverage:** added focused tests for non-syntactic names in:

   - `tests/testthat/test-comparator-score.R`
   - `tests/testthat/test-suggest-blocking.R`
   - `tests/testthat/test-il_cluster_confusion_matrix.R`

## Efficient review order

1. **Start with `R/utils-evaluation.R`.**

   Review the SQL and fallback branches side by side:

   - `labels_from_column()`
   - `score_labeled_pairs()`
   - `compute_confusion_counts()`
   - `summarise_confusion_counts()`

   Focus first on the now-fixed `found_by_blocking` contract:

   - blocking columns not in `comp_names`
   - transformed blocking (`.transform`)
   - SQL-only blocking (`.where`)
   - pairs that are true matches but absent from the candidate set

2. **Then review the public evaluation wrappers.**

   Check that each one is consistent with the shared helper contract:

   - `R/il_accuracy.R`
   - `R/il_confusion_matrix.R`
   - `R/il_errors.R`
   - `R/il_roc.R`
   - `R/il_precision_recall.R`

   In particular, confirm that `il_errors()` now treats blocking-missed true
   pairs as false negatives in the same way `il_accuracy()` and
   `il_confusion_matrix()` do.

3. **Review `R/il_unlinkables.R` before the lower-risk diagnostics.**

   The current implementation now uses one combined unlinkable percentage across
   both tables for non-dedupe models. Reviewers should confirm that this is the
   preferred public contract.

4. **Review `R/il_comparator_score.R` next.**

   Priorities:

   - confirm the DuckDB scale fix
   - confirm the identifier quoting changes
   - decide whether PostgreSQL `similarity()` should remain a compatibility
     alias in the `jaro_winkler` column or should eventually get a distinct name

5. **Then review the blocking diagnostics together.**

   Read these as one surface:

   - `R/il_largest_blocks.R`
   - `R/il_suggest_blocking.R`
   - `block_from_labels()` inside `R/il_suggest_blocking.R`

   Questions to answer:

   - Is the new transformed-grouping behavior in `il_largest_blocks()`
     consistent with the intended API?
   - Are there any remaining diagnostics paths that should inherit the Chunk 7
     quoting helpers?
   - Are link-mode counts and denominators correct for any future multi-table
     extensions here?

6. **Finish with the lower-risk descriptive helpers.**

   These looked more straightforward on a first pass:

   - `R/il_comparison_vectors.R`
   - `R/il_completeness.R`
   - `R/il_profile.R`
   - `R/il_string_similarity.R`
   - `R/il_cluster_confusion_matrix.R`

   The main remaining questions there are SQL quoting and public-contract
   clarity, not an already-confirmed arithmetic bug.

## Remaining review notes

1. PostgreSQL comparator semantics still deserve a human decision.

   The SQL path now has the correct scale and quoting, but PostgreSQL still uses
   `pg_trgm::similarity()` and exposes that score in the `jaro_winkler` column
   for compatibility. That is documented more honestly now, but it remains a
   naming compromise rather than a mathematical match.

2. SQL-only blocking regressions in evaluation are still worth adding later.

   The fallback evaluation bug is fixed by evaluating blocking in SQL, which
   covers `.where` logically, but there is not yet a dedicated regression test
   exercising a raw-SQL blocking condition in this chunk.

## Bottom line

The concrete blockers from the first pass are now fixed. Chunk 8 is in much
better shape for human review, and the best review use of time is to confirm the
new helper boundaries and the remaining PostgreSQL-compatibility decision rather
than re-discovering the earlier defects.
