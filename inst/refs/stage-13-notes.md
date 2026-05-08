# Stage 13 — Whole-package Review and Hardening (Executive Summary)

## Objective

Run a systematic review of the full package surface, fix confirmed
correctness and contract defects, and leave a readable audit trail for
the few remaining design decisions that are better handled explicitly
than implicitly.

## Approach

1. **Review the package in bounded chunks** — split the codebase into 10
   review surfaces so each pass had a clear scope and neighboring
   boundaries ([47](47-review-plan.md)).
2. **Fix confirmed defects, not speculative ones** — each chunk focused
   on issues that could be reproduced from code or behavior, with
   targeted regression coverage added alongside the fixes
   ([48](48-review-chunk-1.md)-[57](57-review-chunk-10.md)).
3. **Make contracts explicit** — where behavior was intentional but easy
   to misread, tighten validation or documentation instead of leaving
   silent edge cases in place.

## Key Changes

### Foundations, comparisons, and transforms (refs
[48](48-review-chunk-1.md), [49](49-review-chunk-2.md),
[50](50-review-chunk-3.md))

The early review passes tightened the package's core object and
comparison contracts. `il_compare()` now resolves tidyselect helpers at
model-attach time instead of storing unresolved selectors, link-mode
models validate right-side columns early, data registration enforces
usable `unique_id` invariants, and empty blocking rules are rejected
before they become downstream SQL failures.

Comparison-level scoring support was filled in where constructor tests
had outpaced active SQL/R behavior: boolean sublevels now evaluate
correctly, `cl_distance_km()` is treated as a real two-column
comparison, threshold ordering/validation is consistent, and
`cl_literal()` escapes SQL safely. Transform handling was hardened at the
same time: SQL paths now error on unsupported custom R transforms rather
than silently dropping them, parameterized transforms escape string
literals correctly, regex group extraction matches between R and SQL, and
dialect-specific transform SQL is explicit.

*Files:* `R/il_compare.R`, `R/il_model.R`, `R/utils-register.R`,
`R/utils-sql.R`, `R/utils-em.R`, `R/il_transform.R`,
`R/il_column_transforms.R`

### Training, scoring, and prediction contracts (refs
[51](51-review-chunk-4.md), [52](52-review-chunk-5.md))

The statistical and scoring core was tightened around explicit model
state. EM estimation now validates blocking and convergence controls
early, `il_estimate_u()` renormalizes after unobserved-level floors,
user-supplied TF tables and labeled-match inputs are validated before
they affect fitted parameters, and mixed independent/dependency-aware
training histories can be combined safely.

Prediction-side APIs were similarly hardened. `predict()` now validates
all public scoring controls and supports `type = "weights"` as a real
fieldwise summary. `il_find_matches()`, `il_score_missing_edges()`,
`il_compare_records()`, and `il_waterfall()` now reject malformed inputs
earlier and reuse the same transform/gamma/TF logic as the main scoring
path. `il_deterministic_link()` was narrowed to the single-table dedupe
surface it actually implements instead of exposing a misleading
multi-table signature.

*Files:* `R/il_estimate_em.R`, `R/il_estimate_u.R`,
`R/il_register_tf.R`, `R/predict.R`, `R/il_find_matches.R`,
`R/il_score_missing_edges.R`, `R/il_compare_records.R`,
`R/il_deterministic_link.R`

### Clustering, SQL infrastructure, and diagnostics (refs
[53](53-review-chunk-6.md), [54](54-review-chunk-7.md),
[55](55-review-chunk-8.md))

The package's SQL-first runtime became more reliable under review.
Clustering now cleans up collected SQL scratch tables, avoids
double-prefixing isolated-node cluster IDs, validates required columns
and thresholds earlier, and treats `source_dataset` mappings as a strict
contract that must be unique and complete when supplied.

The shared SQL layer also absorbed several correctness fixes: SQLite view
registration no longer relies on unsupported syntax, identifier quoting
is applied consistently across registration and generated SQL, and
PostgreSQL date/time difference SQL now uses PostgreSQL expressions
instead of SQLite-style functions. On the diagnostics and evaluation
side, fallback evaluation now resolves blocking in SQL, DuckDB comparator
scores no longer divide already-normalized similarities by 100,
`il_largest_blocks()` respects blocking transforms, `il_unlinkables()`
uses correct link-mode denominators, and several SQL helpers now handle
non-syntactic names safely.

*Files:* `R/il_cluster.R`, `R/utils-cc.R`, `R/utils-sql.R`,
`R/utils-register.R`, `R/utils-evaluation.R`,
`R/il_comparator_score.R`, `R/il_largest_blocks.R`,
`R/il_unlinkables.R`

### Persistence, phonetics, and public narrative (refs
[56](56-review-chunk-9.md), [57](57-review-chunk-10.md))

The later passes cleaned up adjacent correctness and documentation issues
that sit at the package boundary. Soundex handling now matches standard
edge cases in both R and DuckDB, TF and phonetic chart SQL paths quote
identifiers correctly, and the JSON save/load boundary is documented
more honestly as a semantic SQL export/import path rather than a
byte-for-byte reconstruction of the original irelink spec objects.

The vignettes and examples were also brought back in line with the
implemented API. User-facing docs now use exported helpers instead of
directly mutating `model$params`, say when examples depend on DuckDB or
lazy backends, align Splink comparison examples on probability
thresholds where that is the portable contract, and explain
`link_and_dedupe` plus blocking-driven false negatives more explicitly.

*Files:* `R/il_phonetic.R`, `R/il_tf_chart.R`, `R/il_save.R`,
`R/il_comparator_score.R`, `vignettes/`

## Outcome

This stage turned a full-package review into a usable maintenance asset:
one planning note, ten chunk-level audit notes, and a broad set of
contract and correctness fixes across the runtime, SQL layer,
diagnostics, persistence, and docs. By the end of the stage, the
remaining items were mostly explicit product-contract choices for human
review rather than hidden implementation defects.

## Test Results

Each chunk added focused regressions around the defects it confirmed, and
the final documented full-suite reruns still passed. The latest recorded
full-suite result in this stage was 1150 passing tests with 0 failures.

## References

- [47 — manual review plan](47-review-plan.md)
- [48 — chunk 1: foundations](48-review-chunk-1.md)
- [49 — chunk 2: comparison layers](49-review-chunk-2.md)
- [50 — chunk 3: column transforms](50-review-chunk-3.md)
- [51 — chunk 4: EM and parameter estimation](51-review-chunk-4.md)
- [52 — chunk 5: prediction and scoring](52-review-chunk-5.md)
- [53 — chunk 6: clustering](53-review-chunk-6.md)
- [54 — chunk 7: database layer](54-review-chunk-7.md)
- [55 — chunk 8: evaluation and diagnostics](55-review-chunk-8.md)
- [56 — chunk 9: visualization and I/O](56-review-chunk-9.md)
- [57 — chunk 10: integration tests and vignettes](57-review-chunk-10.md)
