# Custom Priors Implementation Notes

Implemented the auxiliary-prior feature.

## Public API

- `il_prior_prevalence(model, probability, strength = NULL)`
  - Sets `model$params$prior` immediately.
  - Stores inspectable metadata in `model$params$priors`.
  - If `strength` is finite, EM applies Beta pseudo-counts during the prior
    update.
- `il_prior_m(model, col, exact = ..., strength = ...)`
  - Adds a matched-class Dirichlet prior for one comparison.
  - `exact` targets the highest gamma level and distributes the remainder using
    current `m` probabilities when available, otherwise uniformly.
- `il_prior_m(model, col, levels = c(...), strength = ...)`
  - Adds a complete named gamma-level distribution.
- `il_constrain_m(model, col, exact = ...)`
  - Adds a fixed matched-class constraint for the strongest gamma level.
  - This is implemented as a hard EM constraint, not as infinite or huge
    pseudo-count strength.
- `il_constrain_m(model, col, levels = c(...))`
  - Adds a complete fixed matched-class distribution.
- `il_priors(model)` and `il_constraints(model)`
  - Return tidy metadata tables for inspection.

## Storage

Regularizing priors live in `model$params$priors` with columns:

- `family`
- `comparison`
- `gamma_level`
- `probability`
- `strength`

Fixed constraints live separately in `model$params$constraints` with columns:

- `family`
- `comparison`
- `gamma_level`
- `probability`

RDS save/load round-trips this metadata through the existing `params` payload.
Splink JSON export remains focused on interoperable Splink settings and does
not encode irelink-only prior metadata. JSON export writes the trained/scoring
settings only; loading that JSON returns empty `il_priors()` and
`il_constraints()` metadata.

## EM Integration

- Prevalence priors are applied in `il_estimate_em()` with Beta pseudo-counts:
  `(sum_w + alpha) / (n_pairs + alpha + beta)`.
- Because irelink uses a blocking-adjusted training prior internally,
  prevalence-prior targets are converted into the same blocking-adjusted space
  for the EM update and then converted back before storage.
- Matched-level priors add Dirichlet pseudo-counts to the `m` update only.
- Fixed matched-class constraints are applied before convergence checks so
  training history records constrained parameter values.
- Partial fixed constraints, such as `exact = 0.99`, fix the targeted level and
  rescale the unconstrained levels from the current EM update.

## Validation And Tests

Added focused tests covering:

- prevalence priors setting the initial prior and pulling fitted prevalence;
- matched-level priors moving exact `m` probabilities down or up as requested;
- field-level fixed constraints holding the requested parameter fixed;
- invalid probabilities, negative strengths, unknown columns, malformed level
  distributions, and non-summing level vectors;
- exact 0/1 prevalence targets, which are rejected because fixed or scoring
  paths would otherwise carry unusable infinite prior odds;
- replacement of one stored prior without dropping unrelated prior rows;
- rejection of priors or constraints on comparisons deactivated by the EM
  blocking rule;
- RDS save/load round-trip of prior and constraint metadata;
- JSON export deliberately omitting irelink-only custom-prior metadata.

## Notes

No blocker was found for the independent Fellegi-Sunter EM implementation.
Dependency-aware scoring does not currently exist in this package, so there is
no dependency-aware prior path to reject yet. If that estimator is added later,
custom priors should error for it until its prior semantics are specified.
