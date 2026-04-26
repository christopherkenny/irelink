# Stage 10 — Testing at Scale (Executive Summary)

## Objective

Harden irelink for large, real-world linkage jobs by stress-testing the
SQL-first pipeline, removing scale-path inefficiencies, and auditing
correctness directly against splink.

## Approach

1. **Audit before optimising** — start with lint and dead-code cleanup,
   then trace every materialisation boundary that could pull too much
   data into R.
2. **Follow the high-volume paths** — inspect 50K-record and
   multi-source lazy-input workflows where integer overflow, duplicate
   work, or unstable IDs only show up at scale.
3. **Re-verify semantics against splink** — compare generated SQL,
   scoring, EM, and clustering behavior line by line, fix real
   divergences, and document intentional ones.

## Key Changes

### Linting and dead-code cleanup (ref [29](29-linting.md))

Started the stage by clearing the full `jarl check .` audit, removing
nearly all lint findings, wiring `canonical_pair_key()` into production,
and deleting unused internal helpers whose only remaining consumers were
tests. This tightened the package before the larger scale and
correctness work began.

*Files:* `R/utils-evaluation.R`, `R/utils-sql.R`, `R/utils-cc.R`,
`tests/testthat/`

### SQL materialisation audits (refs [30](30-sql-audit.md),
[33](33-sql-audit.md))

Two audit rounds pushed more of the high-volume pipeline into SQL:

- EM and `m` estimation now work from aggregated gamma-pattern counts
  instead of pair-level matrices.
- `labels_from_column()` resolves labels with lazy prediction plus a SQL
  join instead of materialising all candidate pairs.
- `predict(collect = TRUE)` on DuckDB/PostgreSQL now reuses the SQL
  scoring path, so only the final filtered result crosses into R.
- `il_unlinkables()` now computes record-level maxima in SQL rather than
  repeatedly filtering full scored-pair tables in R.

This kept SQL as the default execution engine even for collected
prediction and evaluation workflows.

*Files:* `R/il_estimate_em.R`, `R/utils-em.R`, `R/utils-evaluation.R`,
`R/predict.R`, `R/il_unlinkables.R`

### Large-scale scaling fixes (ref [31](31-scaling.md))

The main benchmark-path fixes addressed failures that only appeared on
large jobs:

- integer-overflow bugs in pair counts were removed by switching to
  numeric arithmetic;
- a new `safe_prior()` helper guards both `NULL` and `NA` priors;
- blocking-rule combination was aligned with splink's `UNION ALL`
  strategy;
- expensive early `DISTINCT` work was deferred until scoring or
  aggregation made it cheap;
- `score_labeled_pairs()` stopped computing the same weight expression
  twice in one SQL statement.

Together these changes removed silent overflow, reduced unnecessary
sorting/deduplication work, and kept evaluation code viable on larger
candidate sets.

*Files:* `R/il_count_pairs.R`, `R/il_largest_blocks.R`,
`R/utils-scoring.R`, `R/utils-sql.R`, `R/utils-evaluation.R`

### Splink comparison and correctness audits (refs
[32](32-comparison.md), [34](34-splink-correctness.md),
[35](35-correctness-audit.md))

The stage included both a broad feature/architecture comparison and a
separate independent correctness audit. That work separated intentional
API differences from true translation bugs and led to concrete fixes:

- SQL-side TF adjustment now uses `COALESCE` so one-sided TF values are
  handled like splink;
- percentage-difference thresholds now use the same boundary operator as
  splink;
- prior semantics, EM regularisation, and best-link differences were
  documented explicitly instead of being left ambiguous.

This gave the package a clearer correctness story: fix the places where
results could drift, and document the places where irelink
intentionally differs.

*Files:* `R/utils-sql.R`, `R/utils-tf.R`, `R/il_estimate_em.R`,
`R/utils-cc.R`

### Lazy-input deduplication bug fix (ref [36](36-deduplication-bug.md))

The most important late-stage bug was not in clustering itself but in
row identity. For lazy database-backed inputs without a user-supplied
`unique_id`, irelink had been synthesizing `ROW_NUMBER() OVER ()` inside
views. On re-evaluation, the same logical rows could receive different
IDs across prediction, evaluation, and clustering queries.

The fix was to materialize a table whenever a synthetic `unique_id` must
be created for a database-backed input. That restored stable row
identity across the whole pipeline and resolved the stacked pseudopeople
failure where benchmark outputs had collapsed to `0` predicted pairs and
`0` clusters. Related correctness fixes retained during the same
investigation included storing the reversed global prior after blocked
EM and preserving `cl_null()` as `gamma = -1`.

*Files:* `R/utils-register.R`, `tests/testthat/test-register-data.R`,
`tests/testthat/test-il_accuracy.R`

## Test Results

This stage focused on regression coverage for scale-sensitive paths:
lazy synthetic IDs, SQL-first collection, TF-adjustment edge cases,
percentage-difference boundaries, and benchmark-sized evaluation flows.
By the end of the stage, the stacked pseudopeople benchmark was
internally coherent again instead of collapsing to zero predictions and
zero clusters.

## References

- [29 — Linting audit](29-linting.md)
- [30 — SQL materialisation audit](30-sql-audit.md)
- [31 — Scaling audit and fixes](31-scaling.md)
- [32 — irelink vs splink deep comparison](32-comparison.md)
- [33 — SQL materialisation audit, round 2](33-sql-audit.md)
- [34 — splink correctness comparison](34-splink-correctness.md)
- [35 — independent correctness audit](35-correctness-audit.md)
- [36 — deduplication bug on lazy synthetic IDs](36-deduplication-bug.md)
