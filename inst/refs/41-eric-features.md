# Eric Feature Implementation Summary

This note summarizes the implemented behavior for greedy one-to-one matching, custom EM priors, and dependency-aware EM, based on the package code rather than the package documentation.

## Greedy one-to-one matching before clustering

Greedy matching is implemented as an option on prediction rather than as a separate clustering algorithm.
The entry point is `predict.il_model(..., greedy = TRUE)`, and it is accepted only for models whose `link_type` is `"link"`.
The option is rejected for deduplication models because the resolver is explicitly one-to-one across a left table and a right table.

Prediction first generates candidate pairs from the model's blocking rules, computes comparison gammas, scores the pairs, and applies the requested probability or match-weight threshold.
Only after thresholding does the greedy resolver run.
Thus the greedy step resolves conflicts among the retained candidate links, not among every possible blocked candidate.

The R-side resolver obtains a stable row-order index for each record from the source table or tables.
It sorts candidate pairs by decreasing posterior match probability, then by left source row order, then by right source row order.
It walks that global ordering once, keeping a pair only if neither its left record nor its right record has already been used.
The result is deterministic, one-to-one, and local-greedy with respect to the posterior ordering, not a maximum-weight bipartite matching.
This R-side resolver is used for SQLite and other non-DuckDB or non-PostgreSQL prediction paths, and it is also directly unit-tested as the fallback implementation.

The SQL path implements the same policy for DuckDB and PostgreSQL.
It wraps the scored-pairs query in a recursive CTE, ranks rows by posterior probability and source row order, carries arrays or lists of already-used left and right IDs, and repeatedly selects the next highest-ranked pair whose endpoints remain unused.
The lazy prediction path uses this SQL resolver before materializing the `il_compared_lazy` table.

The clustering code has a distinct best-link mode.
`il_cluster(method = "best_link")` filters the edge set to mutual best links and then runs connected components on the filtered graph.
With `source_dataset`, clustering uses an iterative one-to-one merge algorithm that repeatedly ranks feasible inter-cluster edges, excludes merges that would create duplicate source datasets inside a cluster, keeps mutual best cluster pairs, and merges them under the smaller representative.
This cluster-level procedure is not the same as `predict(..., greedy = TRUE)`: prediction greedily assigns record pairs before clustering, while best-link clustering prunes or merges graph edges after scored pairs already exist.

## Custom prior support in independent EM

Custom priors are stored as model metadata under `model$params$priors`, and fixed matched-class constraints are stored separately under `model$params$constraints`.
They are consumed during independent Fellegi-Sunter EM and are not reapplied during prediction.

`il_prior_prevalence(model, probability, strength = NULL)` validates a strict probability in `(0, 1)`, stores it as the model's current global prior, and upserts a single `"prevalence"` prior row.
If `strength` is `NULL`, the stored probability acts as an initialization or fixed value through the normal prior handling, but it does not contribute pseudo-counts to the EM prior update.
If `strength` is finite and positive, EM uses the target as Beta pseudo-counts for the prior update.

Inside independent EM, the algorithm first adjusts the model's global prior for any comparison columns deactivated by the EM blocking rule.
The adjusted training prior multiplies the prior odds by the Bayes factor of the blocked comparison's highest gamma level.
At the end of EM, the fitted training prior is transformed back to the global prior by dividing out those same blocking-implied Bayes factors.

When an active prevalence prior with positive strength is present and `fix_prior = FALSE`, the M-step updates the training prior as `(sum_w + alpha) / (n_pairs + alpha + beta)`.
Here `sum_w` is the expected number of matches under the current E-step weights, `alpha` is the blocking-adjusted target probability times strength, and `beta` is one minus that blocking-adjusted target probability times strength.
Without such a prior, the training prior update is simply `sum_w / n_pairs`.
If `fix_prior = TRUE`, the prior is not updated by this M-step.

`il_prior_m(model, col, exact = ..., strength = ...)` or `il_prior_m(model, col, levels = ..., strength = ...)` adds a Dirichlet-style regularizing prior for the matched-class `m` distribution of one comparison.
The targeted column must be present as an `il_compare()` layer, strength must be finite and non-negative, and the level distribution must name exactly the comparison's gamma levels and sum to one.
The `exact` form assigns the specified probability to the strongest gamma level and distributes the remaining probability over lower levels using the current fitted `m` distribution when available, otherwise uniformly.

In each independent EM M-step, each active `m` distribution is estimated from posterior-weighted gamma counts plus the package's baseline `0.5` smoothing spread over levels.
For comparisons with a matched-class prior, EM adds `prior_probability_by_level * strength` to the numerator for each level and adds the total prior strength to the denominator.
The resulting vector is floored at `0.001`, renormalized, and then passed through any fixed matched-class constraint.
The `u` distribution has no custom prior path; if `fix_u = FALSE`, it is updated from nonmatch-weighted gamma counts plus the same baseline smoothing.

`il_constrain_m()` is not a regularizing prior.
It stores fixed probabilities for one or more matched-class gamma levels.
After each `m` update, constrained levels are overwritten with their fixed probabilities, and the remaining probability mass is redistributed over unconstrained levels in proportion to the unconstrained raw update, falling back to uniform allocation if necessary.

Prior and constraint targets are checked against the EM blocking rule.
If a target comparison overlaps a blocking column, EM aborts because that comparison is deactivated and its parameters are not being learned in that training pass.
This validation applies to both regularizing matched-class priors and fixed matched-class constraints.

## Conditional dependency weakening in EM

Dependency-aware EM is selected with `il_estimate_em(..., estimator_mode = "dependency-aware")`.
It is a separate estimator path from the independent EM loop, and it rejects controls whose semantics are only implemented for fieldwise independent EM.
The rejected combinations include explicit `fix_u`, explicit `fix_m`, explicit `estimate_without_tf`, `derive_prior = TRUE`, `fix_prior = TRUE`, any stored regularizing priors, any stored fixed constraints, term-frequency comparisons, and EM blocking rules that overlap any comparison column.

Training begins by aggregating blocked candidate pairs to counts of full comparison patterns.
The gamma columns are normalized to integer comparison columns, missing gamma states are preserved as `-1` when a comparison method has an explicit null level, and the support is expanded to the Cartesian product of all compatible levels for all comparisons.
This means the fitted model has a probability for every compatible pattern in the expanded support, including patterns not observed in the EM training table.

Initial matched and unmatched pattern probabilities are built from the current fieldwise parameters when a complete parameter table is available.
Otherwise the initializer uses the usual high-agreement matched default, with `0.9` on the highest gamma level and the remaining `0.1` spread over lower levels, and a uniform unmatched default.
Those fieldwise probabilities are multiplied across observed nonmissing gamma states to form initial joint pattern probabilities over the expanded support, then normalized.
The starting prior is the model prior, with a fallback of `min(0.1, 1 / sum(pattern_counts))`.

Each dependency-aware EM iteration computes a posterior match probability for each observed pattern using the current prior, matched pattern probability, and unmatched pattern probability.
The prior is then updated to the posterior-weighted match count divided by the number of candidate pairs.
There is no Beta prior path and no fixed-prior path in this estimator.

The M-step fits two Poisson-type log-linear models to expanded support counts with a small positive offset of `1e-6`.
The matched-class pattern model is fit with main effects only, using the formula `count ~ .`.
The unmatched-class pattern model is fit with pairwise interactions when there is more than one comparison, using `count ~ (.)^2`.
The fitted GLMs use `quasipoisson()`, and fitting failures are converted into a clear error about sparse or collinear pattern tables.

After each GLM fit, fitted log means are predicted over the full support, exponentiated after subtracting the maximum log value for numerical stability, floored at `1e-12`, and normalized to sum to one.
Observed training patterns then index into these support distributions for the next E-step.
Convergence is measured as the maximum absolute change across the prior, matched support distribution, and unmatched support distribution.

The fitted dependency-aware state is stored under `model$params$dependency_aware`.
It includes the fitted prior, comparison names, level support, formulas, fitted matched and unmatched GLMs, the expanded support, the scored training patterns, convergence status, iteration count, and offset.
The model's ordinary `model$params$prior` is also set to the fitted dependency-aware prior, and `model$params$estimator_mode` is set to `"dependency-aware"`.

Scoring with a dependency-aware model does not sum fieldwise log `m/u` ratios.
Instead, each comparison pattern is converted to the same factor representation, the matched and unmatched log-linear models predict normalized joint probabilities for that pattern, and the match weight is `log2(p_gamma_m / p_gamma_u)`.
The posterior match probability is computed from the fitted prior and these joint pattern probabilities.

For SQL-backed prediction, dependency-aware scoring first collects the distinct gamma patterns produced by the candidate-pair SQL, scores those patterns in R using the fitted log-linear state, writes a temporary pattern-to-score lookup table, and joins candidate pairs back to that lookup on all gamma columns.
This keeps pair-level scoring in SQL while avoiding reimplementing the log-linear prediction machinery in SQL.
