# Dependency-Aware Scoring

Dependency-aware scoring adds an alternative EM estimator to `il_estimate_em()`
for cases where a conditionally independent Fellegi-Sunter model is too
restrictive:

```r
model <- il_estimate_em(
  model,
  block_on(...),
  estimator_mode = "dependency-aware"
)
```

The default remains `estimator_mode = "independent"`.

## Summary

Dependency-aware EM is fit on aggregated comparison-pattern counts from the
existing gamma-count pipeline rather than on pair-level estimation state.
Each pattern is the joint vector of gamma values across the compared fields, with
missing states retained as explicit levels, including `-1` from `cl_null()`
comparisons.

The estimator uses log-linear models for the two latent classes:

- the matched class uses main effects only;
- the unmatched class uses main effects plus pairwise interactions.

A small finite offset keeps the weighted-count GLMs numerically stable, and the
fitted pattern weights are renormalized into matched and unmatched pattern
distributions.
Those distributions are then used to score observed patterns and
map posterior match probabilities back to candidate pairs.

## Model State and Scoring

The fitted dependency-aware state is stored in
`model$params$dependency_aware`.
It includes:

- the comparison names and factor levels used for training and scoring;
- the matched and unmatched GLM fits and their formulas;
- the fitted training-pattern probabilities and posterior match probabilities;
- convergence metadata.

`il_score_patterns()` scores compatible pattern tables, including tables that
contain valid patterns not observed during training. `il_parameters()` returns
the fitted dependency-aware training-pattern table for dependency-aware models.
RDS save/load and `il_attach()` preserve the dependency-aware estimator state.

For DuckDB and PostgreSQL backends, dependency-aware prediction avoids
collecting full candidate-pair tables into R just to score them. `predict()`,
`predict(..., collect = FALSE)`, and `il_find_matches()` first collect only the
distinct observed gamma patterns, score that small pattern table in R, write the
scored lookup back to the database, and join the lookup to candidate pairs in
SQL.

With only one comparison field, both latent-class GLMs reduce to main effects
because there are no pairwise interactions to estimate.

## Scope Limits

Dependency-aware scoring intentionally rejects combinations that do not yet have
coherent joint-pattern semantics:

- regularizing priors from `il_prior_prevalence()` or `il_prior_m()`;
- fixed field constraints from `il_constrain_m()`;
- `fix_prior = TRUE`;
- independent-estimator controls `fix_u`, `fix_m`, `estimate_without_tf`, and
  `derive_prior`;
- EM blocking rules that overlap with compared columns, because those gamma
  values are structurally fixed by blocking;
- field-level term-frequency adjustments;
- Splink settings JSON export.

`il_waterfall()` also rejects dependency-aware scores because a fieldwise
decomposition is not a valid representation of a joint pattern model.

## Coverage

Tests cover:

- scores differing from the independent estimator on dependent-field data;
- missing comparison states as explicit pattern levels;
- scoring compatible pattern tables larger than the training table;
- valid but unobserved gamma levels in multi-level comparisons;
- unsupported priors, constraints, blocking overlaps, independent-only EM
  controls, and term-frequency combinations;
- RDS save/load, attach, collected prediction, lazy prediction, and
  `il_find_matches()` behavior for dependency-aware models.
