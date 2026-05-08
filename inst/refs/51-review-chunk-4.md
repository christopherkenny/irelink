# Chunk 4 review notes

Chunk 4 covers fitted parameter state: EM training, direct m/u/prior
estimation, regularizing priors, term-frequency inputs, training history, and
dependency-aware pattern scoring.

Main files:

- `R/il_estimate_em.R`
- `R/il_estimate_u.R`
- `R/il_estimate_prior.R`
- `R/il_estimate_m_from_column.R`
- `R/il_estimate_m_from_labels.R`
- `R/il_priors.R`
- `R/il_parameters.R`
- `R/il_training_history.R`
- `R/il_register_tf.R`
- `R/utils-em.R`
- `R/utils-tf.R`
- `R/utils-dependency-aware.R`

Important neighboring files inspected for this chunk:

- `R/utils-scoring.R`, for prior clamping, blocking-adjusted priors,
  m/u extraction, match weights, and posterior conversion
- `R/utils-sql.R`, for `build_gamma_query()`, SQL scoring, and TF adjustment
  SQL
- `R/predict.R`, `R/il_find_matches.R`, `R/il_score_missing_edges.R`, and
  `R/il_waterfall.R`, because they consume trained parameter state
- `R/il_save.R`, for independent and dependency-aware fitted-state persistence

Nearby tests:

- `tests/testthat/test-il_estimate.R`
- `tests/testthat/test-em-flex.R`
- `tests/testthat/test-em-options.R`
- `tests/testthat/test-em-prior.R`
- `tests/testthat/test-custom-priors.R`
- `tests/testthat/test-dependency-aware-scoring.R`
- `tests/testthat/test-register-tf.R`
- `tests/testthat/test-term-frequency.R`

## Risk disposition

1. Confirmed issue: `il_estimate_em()` under-validated core controls.

   `il_estimate_em()` read `blocking$columns` before checking that
   `blocking` was an `il_blocking_rule`, and `convergence` was passed directly
   into the stopping comparison. Bad inputs could therefore fail late or
   unclearly.

   Fix: `il_estimate_em()` now errors early unless `blocking` was created by
   `block_on()`, and now requires `convergence` to be a scalar positive finite
   number.

   Tests added: `test-em-options.R` covers invalid blocking input and invalid
   convergence values.

2. Confirmed issue: `il_estimate_u()` did not renormalize after applying the
   unobserved-level floor.

   The function floored unobserved u levels at `1e-6`, but stored the floored
   vector without re-scaling it. This meant per-comparison u probabilities
   could sum above 1.

   Fix: each comparison's u vector is now normalized after applying the
   `1e-6` floor.

   Tests updated: `test-il_estimate.R` now asserts both sum-to-one behavior
   and the renormalized floor values for unobserved levels.

3. Confirmed issue: user-supplied TF tables were under-validated.

   `il_register_tf()` checked only that the required column names were present
   and that overwrite behavior was respected. Malformed TF probabilities could
   be registered and later feed directly into log-weight calculations.

   Fix: `il_register_tf()` now requires the registered column to exist in the
   model data, value keys to be non-missing and unique, and TF probabilities to
   be numeric, finite, non-missing, and in `(0, 1]`.

   Tests added: `test-register-tf.R` covers missing model columns, duplicate
   TF keys, zero probabilities, and missing probabilities.

4. Confirmed issue: `il_estimate_m_from_labels()` under-validated label
   inputs.

   The function assumed the label table had `unique_id_l`, `unique_id_r`, and
   `is_match`, and that `labels$is_match` was directly usable for filtering.
   Malformed labels could therefore fail unclearly or be interpreted
   accidentally.

   Fix: labels must now be a data frame with the required columns. Unique ID
   columns and `is_match` must not contain missing values. `is_match` must be
   logical or numeric `0/1`.

   Tests added: `test-il_estimate.R` covers missing required columns, missing
   match flags, and invalid numeric match flags.

5. Confirmed issue: mixed EM history rows could fail to bind.

   Independent EM stores per-comparison/per-level history rows, while
   dependency-aware EM stores session-level diagnostics with different
   columns. `il_training_history()` used `do.call(rbind, history)`, which could
   fail when a model had both kinds of history.

   Fix: `il_training_history()` now binds the union of history columns and
   fills missing fields with `NA`.

   Tests added: `test-dependency-aware-scoring.R` trains independent EM and
   dependency-aware EM on the same model and verifies that history can be
   collected.

6. Reviewed and left unchanged: `derive_prior = TRUE` can overwrite the stored
   prior even when `fix_prior = TRUE`.

   `fix_prior` controls whether the prior changes during EM iterations.
   `derive_prior` is a post-EM storage step that derives a global prior from
   the fitted parameters. That precedence is coherent, but user-facing docs
   should probably make it explicit.

7. Reviewed and left unchanged: blocked-EM prior adjustment.

   The independent EM path trains with a blocking-adjusted prior and stores
   the global prior by reversing that adjustment after EM. This is intentional:
   the EM prior is conditioned on exact agreement implied by blocked/deactivated
   comparisons, while `model$params$prior` remains a global prior.

   Existing tests in `test-em-prior.R` cover the helper reversibility and
   global-prior storage.

8. Reviewed and left unchanged: dependency-aware estimator restrictions.

   Dependency-aware EM stores fitted log-linear comparison-pattern
   distributions instead of fieldwise m/u rows. It intentionally rejects TF,
   priors, constraints, blocked-out comparison columns, `fix_u`, `fix_m`,
   `fix_prior`, `estimate_without_tf`, and `derive_prior`.

   Existing tests cover incompatible option rejection, missing-state support,
   unobserved-compatible levels, save/load/attach, lazy SQL prediction,
   `il_find_matches()`, and score-table naming.

## Review order

1. Start with parameter-state contracts.

   Trace how this chunk reads and writes `model$params$prior`,
   `model$params$comparisons`, `model$params$history`,
   `model$params$priors`, `model$params$constraints`,
   `model$params$estimator_mode`, `model$params$dependency_aware`,
   `model$params$u_estimation`, and `model$params$sql_profile`.

2. Review shared scoring helpers before EM.

   In `R/utils-scoring.R`, confirm `safe_prior()`, probability clamping,
   blocking-prior adjustment/reversal, `extract_mu_vectors()`,
   `score_gamma_matrix()`, `weight_to_probability()`, and
   `total_match_weight()`. These functions define how trained parameters are
   consumed downstream.

3. Review gamma extraction and aggregation.

   In `R/utils-em.R`, inspect `get_pairs_with_gamma_counts()`,
   `get_pairs_with_gammas()`, `get_random_pairs_with_gammas()`,
   `get_random_pair_gamma_counts_chunked()`, `compute_gamma()`, and
   `compute_gamma_matrix()`. Confirm SQL and R fallback paths produce the same
   gamma patterns and counts for comparison shapes from Chunks 2 and 3.

4. Review independent parameter estimation.

   Start with `il_estimate_u()`, then `il_estimate_em()`, then
   `il_estimate_prior()`. For EM, focus on warm starts, fixed controls,
   deactivated blocked columns, m priors, prevalence priors, fixed m
   constraints, convergence, and global-prior reversal.

5. Review supervised m estimation.

   Compare `il_estimate_m_from_labels()` and
   `il_estimate_m_from_column()`. They duplicate aggregation and parameter
   merge logic, so check SQL/R fallback parity, smoothing, normalization, and
   behavior for missing labels, missing IDs, duplicate pairs, and link-mode
   models.

6. Review TF behavior.

   Inspect `compute_tf_tables()`, `il_register_tf()`, `sql_tf_select_exprs()`,
   `lookup_tf_r()`, `compute_tf_adjustment()`, and prediction SQL. Then return
   to `estimate_without_tf = FALSE` in `il_estimate_em()` and verify
   training-time TF adjustment matches prediction-time scoring.

7. Review dependency-aware estimation last.

   Treat it as a separate estimator family. Review
   `il_estimate_em_dependency_aware()`, pattern normalization, support
   expansion, initialization, log-linear fitting, `il_score_patterns()`, SQL
   score lookup generation, prediction, find-matches, save/load, and history.

## Manual checks covered

- Invalid EM `blocking` input now errors as a blocking-rule validation problem.
- Invalid EM `convergence` input now errors before pair generation.
- `fix_u = TRUE, fix_m = TRUE` still errors.
- Blocked comparisons targeted by m priors or fixed constraints still error
  clearly as deactivated targets.
- Blocked EM still stores the global prior after reversing the training-time
  blocking adjustment.
- `derive_prior = TRUE` remains a post-EM override of the stored prior.
- `il_estimate_u()` now stores normalized u distributions after applying
  unobserved-level floors.
- `il_estimate_m_from_labels()` now validates required columns, missing IDs,
  missing match flags, and non-logical/non-`0/1` match flags.
- `il_register_tf()` now rejects missing model columns, duplicate or missing
  TF keys, and invalid TF probabilities.
- `il_training_history()` now supports a model with both independent and
  dependency-aware EM history rows.
- Dependency-aware prediction and `il_find_matches()` still use scoped SQL
  score lookup tables.

## Remaining review focus

1. Add direct coverage for pair-level TF-inclusive EM
   (`estimate_without_tf = FALSE`), not only prediction-time TF adjustment.

2. Decide and document `derive_prior` precedence when `fix_prior = TRUE`.
   The current implementation is coherent but easy to misread.

3. Review link-mode behavior for `il_estimate_m_from_labels()` and
   `il_estimate_m_from_column()`.

4. Decide whether duplicate/reversed label pairs and labels pointing at
   missing records should be rejected, deduplicated, or treated as
   caller-owned.

5. Consider documenting that custom prior metadata is RDS-only and not Splink
   JSON portable; tests already assert this behavior.

6. Consider documenting that dependency-aware scores are not field-decomposable
   in the same way as independent match weights.

## Verification

Focused tests passed after fixes:

- `test-em-options.R`: 11 passed
- `test-il_estimate.R`: 33 passed
- `test-register-tf.R`: 11 passed
- `test-dependency-aware-scoring.R`: 35 passed

Full suite also passed after the fixes:

- 1054 passed
- 15 skipped
- 0 failed
- 0 warnings
