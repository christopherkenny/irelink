Greedy matching adds an optional one-to-one post-processing step for link predictions.

`predict.il_model()` now accepts `greedy = FALSE` by default. When
`greedy = TRUE`, prediction returns a deterministic one-to-one matching for
`link` models instead of all above-threshold candidate pairs.

The greedy resolver works after scoring and thresholding:

1. Sort candidate pairs by descending `match_probability`.
2. Break ties by the left-table row order used when the data was registered.
3. Break any remaining ties by the right-table row order.
4. Walk the sorted pairs once, keeping a pair only if neither record has already been matched.

This makes the output deterministic and keeps the highest-posterior links first, even when `unique_id` values are not in row order.

Implementation notes:

- The tie-break uses source row order rather than `unique_id`, so arbitrary record IDs do not affect deterministic matching.
- Greedy matching is currently restricted to `link` models because dedupe and link-and-dedupe need different semantics.
- `collect = FALSE` still returns an `il_compared_lazy` result. Greedy matching is resolved in SQL, so the scored candidate set is not collected into R.

Test coverage added for:

- global greedy selection behavior,
- one-to-one uniqueness on both sides,
- deterministic tie-breaking by row order instead of `unique_id`,
- preserving existing behavior when `greedy = FALSE`.
