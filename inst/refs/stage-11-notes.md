# Stage 11 — Requested Features (Executive Summary)

## Objective

Implement the requested feature set around prediction-time one-to-one
matching, custom EM priors, and dependency-aware estimation while
preserving irelink's SQL-first execution model and explicit model state.

## Approach

1. **Add features as opt-in extensions** — keep existing defaults
   unchanged, and put new behavior behind explicit arguments or helper
   APIs.
2. **Keep state inspectable** — store new priors, constraints, and
   dependency-aware fit objects in `model$params` so save/load and
   follow-on tools can see the exact fitted state.
3. **Reject incoherent combinations** — when a feature's semantics are
   not well-defined, error clearly rather than silently approximating.

## Key Changes

### Greedy one-to-one prediction (ref [37](37-greedy-matching.md))

`predict.il_model()` now accepts `greedy = TRUE` for `link` models,
adding a deterministic one-to-one post-processing step after scoring and
thresholding. Candidate pairs are ordered by descending posterior match
probability, then by source row order on the left and right tables, and
selected greedily if neither endpoint has already been used.

The feature stays SQL-first on DuckDB/PostgreSQL, where greedy matching
is resolved in SQL for both lazy and collected prediction paths.
Collected SQLite and other fallback paths use an R implementation with
the same ordering rules. This is deliberately separate from
`il_cluster(method = "best_link")`, which remains a graph/clustering
operation rather than a prediction-time resolver.

*Files:* `R/predict.R`, `R/utils-sql.R`,
`tests/testthat/test-predict.R`

### Custom priors and constraints for independent EM (ref
[38](38-custom-priors.md))

Independent Fellegi-Sunter EM gained a full custom-prior layer:

- `il_prior_prevalence()` adds prior-match prevalence metadata and
  optional Beta pseudo-count strength;
- `il_prior_m()` adds matched-class Dirichlet-style priors for one
  comparison;
- `il_constrain_m()` adds hard matched-class constraints;
- `il_priors()` and `il_constraints()` expose the stored metadata.

These priors are integrated into EM rather than being post-hoc
annotations. Prevalence priors are converted into the same
blocking-adjusted space used during EM, matched-class priors alter the
`m` updates directly, and hard constraints are re-applied before
convergence checks. The extra metadata round-trips through RDS save/load
but is intentionally excluded from Splink JSON export.

*Files:* `R/il_priors.R`, `R/il_estimate_em.R`, `R/il_save.R`

### Dependency-aware EM and pattern scoring (ref
[39](39-dependency-aware-scoring.md))

`il_estimate_em(..., estimator_mode = "dependency-aware")` adds a second
estimation mode for cases where comparison fields are not conditionally
independent. Instead of learning only per-field `m` and `u`
distributions, this path fits matched and unmatched log-linear models
over aggregated comparison-pattern counts, preserving explicit missing
states and scoring whole gamma patterns jointly.

For DuckDB and PostgreSQL, prediction remains SQL-first: irelink scores
the distinct observed gamma patterns in R, writes the small scored
lookup back to the database, and joins it to candidate pairs in SQL.
The implementation also defines clear scope limits, rejecting
combinations such as field-level term-frequency adjustments, blocking
rules that overlap compared columns, fixed-prior mode, and independent
EM-only controls.

*Files:* `R/il_estimate_em.R`, `R/utils-dependency-aware.R`,
`R/predict.R`, `R/il_find_matches.R`, `R/il_parameters.R`,
`R/il_save.R`

### Consolidated semantics for the requested feature set (ref
[40](40-eric-features.md))

The final implementation note ties the new features together and makes
their boundaries explicit:

- greedy matching is local greedy assignment over thresholded prediction
  output, not maximum-weight bipartite matching;
- custom priors are independent-EM metadata consumed during training,
  while fixed constraints are applied after each `m` update;
- dependency-aware EM is a separate estimator path with joint-pattern
  semantics, different scoring logic, and deliberate incompatibility
  checks.

This consolidation matters because the requested features overlap in the
same training and prediction surfaces. The stage ended with those
interactions documented from code rather than inference.

## Test Results

Coverage was added for greedy one-to-one uniqueness and tie-breaking,
custom-prior validation and persistence, constrained `m` updates,
dependency-aware save/load and prediction, scoring of valid unobserved
patterns, and explicit rejection of unsupported feature combinations.

## References

- [37 — greedy matching](37-greedy-matching.md)
- [38 — custom priors](38-custom-priors.md)
- [39 — dependency-aware scoring](39-dependency-aware-scoring.md)
- [40 — integrated requested-feature summary](40-eric-features.md)
