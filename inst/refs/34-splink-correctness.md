# splink Correctness Comparison

Systematic comparison of irelink and splink to identify places where a
small mistranslation could silently change results.  Each row in the
summary table links to a detailed subsection below.

## Summary Table

| investigation | irelink path | splink path | status | risk | action | summary |
|---|---|---|---|---|---|---|
| Scoring formula (match_weight) | `R/utils-sql.R:907-1053` | `splink/internals/predict.py:70-220` | correct | low | none | Both sum log2(m/u) per level; irelink additively, splink multiplicatively in linear domain. Mathematically identical. |
| match_weight prior semantics | `R/utils-sql.R:1007-1048` | `splink/internals/predict.py:92-115` | intentional difference | medium | document | irelink `match_weight` excludes prior (pure evidence); splink includes prior. `match_probability` identical in both. |
| match_probability transform | `R/utils-sql.R:1032-1043` | `splink/internals/predict.py:208-218` | correct | none | none | Both compute `BF/(1+BF)`. irelink via `1/(1+exp(-x))`; splink via algebraic form with Infinity guard. Equivalent. |
| TF adjustment SQL | `R/utils-sql.R:931-958` | `splink/internals/comparison_level.py:576-643` | correct | none | none | Both compute `w * log2(u_exact / max(tf_l, tf_r))` (irelink additive log2; splink `POW(u/tf, w)` multiplicative). Equivalent. |
| TF minimum u floor | `R/utils-sql.R:940-946` | `splink/internals/comparison_level.py:610-630` | correct | none | none | Both floor the TF divisor at `tf_minimum_u_value`. Different SQL shapes; same semantics. |
| TF table computation | `R/utils-tf.R:28-80` | `splink/internals/term_frequencies.py:33-48` | correct | none | none | Both compute `COUNT/SUM` per value. irelink handles link/dedupe modes separately; splink concatenates first. Same values. |
| TF adjustment scope | `R/utils-sql.R:952, R/utils-scoring.R:118-161` | `splink/internals/comparison_level.py:586-591` | correct | none | none | Both apply TF only at the highest gamma level (exact match) for each comparison. Other levels get identity (0 or 1.0). |
| Gamma CASE generation | `R/utils-sql.R:220-280` | `splink/internals/comparison.py:243-264` | correct | none | none | Both generate CASE WHEN with highest gamma first. irelink packs into one CASE; splink assembles from per-level fragments. Same output. |
| NULL guard on comparisons | `R/utils-sql.R:231` | `splink/internals/comparison_level_library.py:88-122` | intentional difference | low | none | irelink always prepends `IS NOT NULL` guard → gamma 0 on any NULL. splink requires explicit `NullLevel()` for gamma −1. Correct simplification. |
| Gamma numbering | `R/utils-sql.R:260-275` | `splink/internals/comparison.py:89-106` | correct | none | none | Both assign highest gamma to strictest level, 0 to ELSE. irelink 1-indexed internally but 0-indexed in SQL. Consistent. |
| Blocking SQL (preceding-rule exclusion) | `R/utils-sql.R:505-575` | `splink/internals/blocking.py` | correct | none | none | Both use UNION ALL with NOT EXISTS exclusion of preceding rules. Same deduplication logic. |
| Blocking dedup (DISTINCT) | `R/utils-sql.R:1040-1041` | `splink/internals/predict.py:113-119` | correct | none | none | irelink applies `SELECT DISTINCT` on the outer scored query. splink relies on upstream dedup. Both produce unique pairs. |
| Lower-ID-on-LHS (dedupe) | `R/utils-sql.R:659` | `splink/internals/blocking.py` | correct | none | none | irelink enforces `l.unique_id < r.unique_id` at SQL generation time; splink swaps columns post-hoc. Same result, irelink more efficient. |
| Comparison: exact match | `R/cl_exact.R` | `splink/internals/comparison_level_library.py:235-294` | correct | none | none | Both: `l.col = r.col`. Match. |
| Comparison: Levenshtein | `R/cl_levenshtein.R` | `splink/internals/comparison_level_library.py:407-484` | correct | none | none | Both: `levenshtein(l.col, r.col) <= threshold`. |
| Comparison: Damerau-Levenshtein | `R/cl_damerau_levenshtein.R` | `splink/internals/comparison_level_library.py:487-567` | correct | none | none | Both: `damerau_levenshtein(l.col, r.col) <= threshold`. |
| Comparison: Jaro-Winkler | `R/cl_jaro_winkler.R` | `splink/internals/comparison_level_library.py:570-610` | correct | low | none | irelink: `jaro_winkler_similarity()`; splink: `jaro_winkler_similarity()`. Both use DuckDB native function. Threshold: `>=`. |
| Comparison: Jaccard | `R/cl_jaccard.R` | `splink/internals/comparison_level_library.py:712-760` | correct | none | none | Both: `jaccard(l.col, r.col) >= threshold`. |
| Comparison: numeric diff | `R/cl_numeric_diff.R` | `splink/internals/comparison_level_library.py:863-927` | correct | none | none | Both: `ABS(l.col - r.col) <= threshold`. irelink CASTs to DOUBLE. |
| Comparison: percentage diff | `R/cl_percentage_diff.R` | `splink/internals/comparison_level_library.py:930-1003` | correct | none | none | Both: `ABS(l-r) / GREATEST(l,r) <= threshold`. Both guard against division by zero. |
| Comparison: date diff | `R/cl_date_diff.R` | `splink/internals/comparison_level_library.py:1006-1100` | correct | none | none | Both: `ABS(date_l - date_r)` with TRY_CAST (DuckDB) or JULIANDAY (SQLite). |
| Comparison: columns reversed | `R/cl_columns_reversed.R` | `splink/internals/comparison_level_library.py:363-403` | correct | none | none | Both support symmetrical and asymmetrical modes. Same SQL. |
| Comparison: array intersect | `R/cl_array_intersect.R` | `splink/internals/comparison_level_library.py:762-860` | correct | none | none | Both: `list_intersect` count `>= threshold`. |
| EM: aggregated pattern counts | `R/utils-em.R:15-62` | `splink/internals/expectation_maximisation.py:27-41` | correct | none | none | Both GROUP BY gamma patterns. irelink has R fallback for SQLite; splink SQL-only. Same aggregation. |
| EM: E-step formula | `R/il_estimate_em.R:233-281` | `splink/internals/predict.py:131-193` | correct | none | none | Both: `w = prior × Π m / (prior × Π m + (1-prior) × Π u)`. irelink in log-space; splink via SQL BF. Equivalent. |
| EM: M-step regularisation | `R/il_estimate_em.R:296-324` | `splink/internals/expectation_maximisation.py:44-86` | intentional difference | low | none | irelink adds Beta(0.5/nl) Dirichlet pseudo-counts + 0.001 floor; splink uses raw empirical proportions. irelink more robust to unobserved levels. |
| EM: convergence criterion | `R/il_estimate_em.R:334-349` | `splink/internals/expectation_maximisation.py:330-333` | correct | none | none | Both check max absolute parameter change. |
| EM: convergence tolerance default | `R/il_estimate_em.R:87` | `splink/internals/settings_creator.py:33` | intentional difference | low | none | irelink 1e-5; splink 1e-4. irelink stricter (more iterations, same results). |
| EM: max iterations default | `R/il_estimate_em.R:89` | `splink/internals/settings_creator.py:34` | correct | none | none | Both default to 25. |
| EM: blocking-adjusted prior | `R/il_estimate_em.R:216-226` | `splink/internals/em_training_session.py:290-320` | correct | none | none | Both multiply prior odds by m_top/u_top for each deactivated column. Same formula. |
| EM: deactivated columns | `R/il_estimate_em.R:128-147, 241` | `splink/internals/em_training_session.py:99-122` | correct | none | none | irelink skips in loop; splink pre-filters list. Same effect. |
| EM: fix_u / fix_m | `R/il_estimate_em.R:87-101, 296-324` | `splink/internals/em_training_session.py:47-96` | correct | none | none | Both support fixing m/u globally. splink additionally supports per-level fix flags; irelink does not. Not a bug. |
| EM: prior update per iteration | `R/il_estimate_em.R:290-294` | `splink/internals/expectation_maximisation.py:97-100` | correct | none | none | Both update prior = sum(match_weights) / n_pairs unless fixed. |
| CC: iterative rep propagation | `R/utils-cc.R:51-176` | `splink/internals/connected_components.py:168-315` | correct | none | none | Both use min-representative propagation with stable/unstable split. Same algorithm (from same paper). |
| CC: convergence check | `R/utils-cc.R:156-159` | `splink/internals/connected_components.py:298-308` | correct | none | none | irelink counts remaining cross-cluster edges; splink counts unstable nodes. Both converge identically. |
| CC: empty edge set | `R/utils-cc.R:194-199` | `splink/internals/connected_components.py` | correct | none | none | Both handle gracefully (return empty result). |
| Clustering: threshold application | `R/utils-cc.R:23-38` | `splink/internals/connected_components.py:163-165` | intentional difference | low | none | irelink filters in R before upload; splink filters in SQL WHERE. Same result, splink more memory-efficient on huge datasets. |
| Clustering: cluster_id format | `R/il_cluster.R:148` | `splink/internals/connected_components.py:323` | intentional difference | none | none | irelink prefixes `cluster_`; splink uses raw representative. Cosmetic. |
| Best-link: tie-breaking | `R/utils-cc.R:316-317` | `splink/internals/one_to_one_clustering.py:229-234` | correct | none | none | Both break ties by smallest partner ID. irelink `ROW_NUMBER()` + `ORDER BY prob DESC, partner`; splink `RANK()` + `ORDER BY prob DESC, r.node_id`. Equivalent given unique IDs. |
| Best-link: architecture | `R/utils-cc.R:265-338` | `splink/internals/one_to_one_clustering.py:103-338` | intentional difference | low | none | irelink: single-pass mutual best-link filter then CC. splink: iterative merging within CC. Both valid; splink more expressive for multi-source. |
| Graph metrics | `R/utils-cc.R:659-717` | `splink/internals/graph_metrics.py:277-315` | correct | none | none | Identical formulas: density, degree, centralisation. |
| estimate_u: random sampling | `R/il_estimate_u.R:64-117` | `splink/internals/estimate_u.py:67-150` | correct | none | none | Both sample random pairs and compute level frequencies. Same approach. |
| estimate_u: u floor | `R/il_estimate_u.R:92` | `splink/internals/estimate_u.py` | intentional difference | low | none | irelink floors at 1e-6; splink allows u=0. irelink more robust. |
| estimate_prior | `R/il_estimate_prior.R:66-105` | `splink/internals/linker_components/training.py:41-166` | correct | none | none | Both: matches = blocked_pairs / recall; prior = matches / total_pairs. irelink clamps [1e-6, 1-1e-6]; splink warns. |
| Default prior | `R/utils-scoring.R:8` | `splink/internals/settings_creator.py:32` | correct | none | none | Both default to 0.0001. |
| Default m/u initialisation | `R/il_estimate_em.R:189-191` | `splink/internals/comparison_level.py:72-93` | intentional difference | low | none | irelink: m = [uniform low, ..., 0.9], u = uniform. splink: m/u via interpolated Bayes factors. Both converge under EM. |
| Link type handling | `R/il_model.R:47` | `splink/internals/settings_creator.py:24` | correct | none | none | Both support dedupe, link, link_and_dedupe. Naming differs (`dedupe` vs `dedupe_only`). |
| Unique ID handling | `R/utils-register.R:53, 133` | `splink/internals/settings.py:74-82` | correct | none | none | Both auto-generate ROW_NUMBER if missing. splink supports composite IDs (unique_id + source_dataset); irelink uses single column. |
| Empty dataset handling | `R/utils-register.R:32, 86, 127` | `splink/internals/settings.py` | correct | none | none | Both reject zero-row datasets with clear error. |
| predict include_fields default | `R/predict.R:93` | `splink/internals/predict.py:49` | intentional difference | low | none | irelink defaults `FALSE` (performance); splink defaults `TRUE`. Not a bug; documented API choice. |
| Infinity handling in scoring | `R/utils-sql.R:908` | `splink/internals/predict.py:213, 217` | correct | none | none | irelink clamps m/u at 1e-10 preventing Inf. splink uses LEAST/GREATEST bounds and explicit Infinity CASE. Both robust. |

## Investigation Details

### Scoring formula (match_weight)

**Checked**: Both packages' SQL generation for per-comparison weight
expressions and how they combine into a total match weight.

**irelink** (`sql_weight_case`, utils-sql.R:907-915): Generates a CASE
expression that maps each gamma level to `log2(m/u)` and sums all
comparison weights additively:

```sql
CAST(CASE gamma_col WHEN 0 THEN w0 WHEN 1 THEN w1 ... ELSE 0.0 END AS DOUBLE)
```

Total: `weight_1 + weight_2 + ... + tf_adj_1 + ...`

**splink** (comparison_level.py:565-574, predict.py:92-209): Generates
per-comparison Bayes factor CASE expressions in the linear domain
(`m/u`) and multiplies them together, then takes `log2()`:

```sql
log2(cast(prior_bf as float8) * bf_1 * bf_2 * ... * tf_1 * tf_2)
```

**Why correct**: `log2(∏ m_j/u_j) = Σ log2(m_j/u_j)`. The additive log2
form and multiplicative linear form are algebraically identical. TF
adjustments follow the same equivalence: `log2(POW(u/tf, w)) = w * log2(u/tf)`.

---

### match_weight prior semantics

**Checked**: Whether the prior probability is included in the
`match_weight` output column.

**irelink** (utils-sql.R:1007-1048): `match_weight` = sum of
`log2(m/u)` across all comparisons + TF adjustments. The prior is
**not** included. It is applied only in the `match_probability`
transform:

```sql
1.0 / (1.0 + EXP(-(log_prior_odds + match_weight * ln2)))
```

**splink** (predict.py:92-115): `match_weight` = `log2(prior_odds ×
∏ BF)`. The prior **is** included:

```sql
log2(cast(prior_bf as float8) * bf_1 * bf_2 * ...)
```

**Impact**: `match_weight` values differ by a constant
`log2(prior/(1−prior))` between the two packages. With the default prior
of 0.0001, this offset is ≈ −13.29.

`match_probability` is identical in both packages (both correctly
incorporate the prior).

`threshold_match_weight` has different semantics: in irelink it filters
on evidence-only weight; in splink on prior-inclusive weight.

**Why not a bug**: This is an intentional API design choice. irelink's
match_weight represents the pure Fellegi–Sunter composite weight (sum of
log-likelihood ratios), which is the traditional definition. Users should
not port `threshold_match_weight` values between packages without
adjustment.

---

### match_probability transform

**Checked**: Final probability computation.

**irelink**: `1/(1+exp(−(log(prior/(1−prior)) + match_weight × ln(2))))`
where `match_weight` excludes the prior.

**splink**: `BF/(1+BF)` where `BF = prior_odds × ∏(m/u)`, plus a CASE
guard for Infinity.

**Why correct**: Both evaluate to
`prior × ∏(m/u) / (prior × ∏(m/u) + (1−prior) × 1)`. The logistic and
algebraic forms are equivalent. irelink avoids Infinity by clamping m/u
at 1e-10; splink handles Infinity explicitly in SQL.

---

### TF adjustment SQL

**Checked**: The SQL expression generated for term-frequency adjustments.

**irelink** (`sql_tf_adj_expr`, utils-sql.R:931-958):

```sql
CASE WHEN gamma_col = max_level
  AND tf_col_l IS NOT NULL AND tf_col_r IS NOT NULL
  AND GREATEST(tf_col_l, tf_col_r) > 0
THEN log2_u - LN(GREATEST(tf_col_l, tf_col_r)) / ln2
ELSE 0.0 END
```

Returns an additive log2 adjustment.

**splink** (comparison_level.py:632-641):

```sql
WHEN gamma_col = level THEN
  CASE WHEN tf EXISTS THEN
    POW(u_exact / GREATEST(tf_l, tf_r), tf_weight)
  ELSE 1.0 END
```

Returns a multiplicative Bayes-factor adjustment.

**Why correct**: `log2(POW(u/tf, w)) = w × log2(u/tf)`, which is exactly
what irelink computes. The additive (irelink) and multiplicative (splink)
formulations are algebraically equivalent because one operates in the
log2 domain and the other in the linear domain.

---

### TF minimum u floor

**Checked**: How both packages apply a floor on the TF denominator.

**irelink** (utils-sql.R:940-946): `GREATEST(GREATEST(tf_l, tf_r), tf_min)`.

**splink** (comparison_level.py:610-630): Multi-arm CASE that checks
whether `max(tf_l, tf_r) > tf_min` before selecting the divisor.

**Why correct**: Both ensure the TF divisor is at least `tf_minimum_u_value`,
preventing division by near-zero term frequencies. The SQL shapes differ
but produce identical values.

---

### TF table computation

**Checked**: How term frequency tables are built.

**irelink** (utils-tf.R:28-80): For dedupe, computes `COUNT(*)/SUM(COUNT(*))`
over the single table. For link mode, computes separately for each dataset.

**splink** (term_frequencies.py:33-48): Always concatenates datasets first,
then computes frequencies over the combined set.

**Why correct**: For dedupe mode the approaches are identical. For link
mode, irelink computes TF per-dataset while splink uses the union. Both
are valid — per-dataset TF is arguably more accurate when dataset
distributions differ.

---

### TF adjustment scope

**Checked**: Which gamma levels receive TF adjustment.

Both packages apply TF adjustment **only at the highest gamma level**
(exact match). All other levels receive the identity adjustment (0 in
log2 domain / 1.0 as multiplier). This is consistent with the Fellegi-
Sunter TF adjustment rationale: TF should only modify the weight of
exact matches, not partial matches.

---

### Gamma CASE generation

**Checked**: SQL CASE statement structure for gamma assignment.

**irelink** (`sql_gamma_case`, utils-sql.R:220-280): Generates a single
CASE with WHENs ordered from strictest to most lenient threshold.
Each WHEN includes a NULL guard (`IS NOT NULL`). ELSE clause maps to
gamma 0.

**splink** (comparison.py:243-264): Assembles CASE from per-level SQL
fragments. Each ComparisonLevel contributes one WHEN clause. Order
determined by `comparison_vector_value` (highest first).

**Why correct**: Both produce the same gamma assignment for any input row.
Ordering and structure differ cosmetically but semantics match.

---

### NULL guard on comparisons

**Checked**: How NULL/missing values are handled in comparison SQL.

**irelink**: Universally prepends `l.col IS NOT NULL AND r.col IS NOT NULL`
to every non-null comparison level. When both values are present, the
comparison proceeds normally. When either is NULL, the row falls through
to ELSE (gamma 0). An explicit `cl_null()` level can be placed first to
assign gamma −1 to NULL pairs.

**splink**: Requires an explicit `NullLevel()` in the comparison level list.
Without it, NULLs fall through to ELSE (gamma 0). With it, NULL pairs
get gamma −1.

**Why correct**: The default behaviour (gamma 0 for NULLs without an
explicit null level) is identical. irelink's universal guard is a
correct simplification that produces the same output.

---

### Blocking SQL (preceding-rule exclusion)

**Checked**: How multiple blocking rules are combined.

Both packages use UNION ALL with a NOT EXISTS exclusion clause that
prevents pairs generated by rule N from appearing in rule N+1's output.
This avoids counting any pair more than once across blocking rules.

---

### EM: aggregated pattern counts

**Checked**: How pair-level data is aggregated for EM.

Both GROUP BY all gamma columns and COUNT the number of pairs per
pattern. irelink's `get_pairs_with_gamma_counts()` (utils-em.R:15-62)
does this in SQL for DuckDB/PostgreSQL and falls back to R-side
aggregation for SQLite. splink does it purely in SQL.

**Why correct**: GROUP BY + COUNT produces identical aggregate counts
regardless of where the computation runs.

---

### EM: E-step formula

**Checked**: The posterior match-probability computation per agreement
pattern.

**irelink** (il_estimate_em.R:233-281): Works in log-space for numerical
stability. Computes `log_match = log(prior) + Σ log(m_j[γ_j])` and
`log_nonmatch = log(1−prior) + Σ log(u_j[γ_j])`, then
`w = exp(log_match − max) / (exp(log_match − max) + exp(log_nonmatch − max))`.

**splink** (predict.py:131-193): Computes Bayes factors in SQL and
converts to match probability via `BF/(1+BF)`.

**Why correct**: Both evaluate the same Bayesian posterior:
`P(M|γ) = prior × ∏ m / (prior × ∏ m + (1−prior) × ∏ u)`. irelink's
log-sum-exp trick avoids floating-point underflow.

---

### EM: M-step regularisation

**Checked**: How updated m/u parameters are computed.

**irelink** (il_estimate_em.R:296-324): Adds Beta(0.5/nl, 0.5/nl)
pseudo-counts to each level's weighted count, then floors at 0.001 and
renormalises:

```
raw[k] = (Σ w_i n_i 1[γ=k] + 0.5/nl) / (Σ w_i n_i + 0.5)
raw = pmax(raw, 0.001)
raw = raw / sum(raw)
```

**splink** (expectation_maximisation.py:44-86): Uses pure empirical
proportions with no regularisation. Unobserved levels receive a string
sentinel (`LEVEL_NOT_OBSERVED_TEXT`).

**Why correct**: irelink's regularisation is a deliberate design choice
that prevents degenerate zero probabilities and log(0) errors. This is
more robust than splink's approach for sparse data.

---

### EM: blocking-adjusted prior

**Checked**: How the prior is adjusted when comparisons overlap with
the training blocking rule.

**irelink** (il_estimate_em.R:216-226): For each deactivated comparison,
multiplies the prior odds by `m_top/u_top` (the Bayes factor of the
highest gamma level). Recomputed at each EM iteration with current m/u.

**splink** (em_training_session.py:290-320): Same formula
(`_bayes_factor * adj_bayes_factor`) but computed once at session
initialisation with initial m/u values.

**Why correct**: Both use the same adjustment formula. irelink's
per-iteration recalculation is slightly more accurate as m/u evolve
during training; splink's static adjustment is a simplification that
converges to the same result in practice.

---

### EM: deactivated columns

**Checked**: How comparisons overlapping the training blocking rule are
excluded.

**irelink**: Identifies overlapping columns (il_estimate_em.R:128-147),
then skips them in the E-step and M-step loops via `if (deactivated[j]) next`.

**splink**: Pre-filters the comparison list before entering the EM loop
(em_training_session.py:116-122).

**Why correct**: Both produce the same result — deactivated comparisons
contribute no information to E-step or M-step. The implementation
differs but the effect is identical.

---

### CC: iterative representative propagation

**Checked**: The core connected-components algorithm.

Both packages implement the same algorithm from the same reference paper
(arXiv:1802.09478). Each iteration:

1. Computes new representative = MIN(current_rep, neighbour_reps)
2. Splits nodes into stable (no outgoing cross-cluster edges) and unstable
3. Filters the edge list to only cross-cluster edges
4. Repeats until no cross-cluster edges remain

The SQL is structurally equivalent with minor table-naming differences.

---

### Best-link: tie-breaking

**Checked**: How tied match probabilities are resolved in best-link
filtering.

**irelink** (utils-cc.R:316-317):
`ROW_NUMBER() OVER (PARTITION BY node ORDER BY prob DESC, partner)`

**splink** (one_to_one_clustering.py:229-234):
`RANK() OVER (PARTITION BY l.representative ORDER BY match_probability DESC, r.node_id)`

Both break ties by the smallest partner/neighbour ID. `ROW_NUMBER()` and
`RANK()` are equivalent here because `(prob, partner)` is unique when
partner is a unique ID.

---

### Best-link: architecture

**Checked**: Overall one-to-one clustering strategy.

**irelink**: Single-pass mutual best-link filter → CC. Simple, correct
for single-dataset deduplication.

**splink**: Iterative one-to-one merging that is cluster-aware and
supports multi-source dataset constraints. More expressive.

**Why not a bug**: Different architectures suited to different use cases.
For single-dataset dedupe both produce the same clusters. For multi-source
linking, splink's iterative approach is more sophisticated.

---

### estimate_u: random sampling

**Checked**: u-parameter estimation.

Both packages sample random pairs (default 1e6), compute gamma levels,
and estimate u as the frequency of each level. irelink floors u at 1e-6
(il_estimate_u.R:92) to prevent log(0) errors; splink does not floor.

---

### estimate_prior

**Checked**: Prior probability estimation.

Both use the formula: `prior = (n_blocked_pairs / recall) / total_pairs`.
irelink clamps to [1e-6, 1−1e-6]; splink warns for extreme values.
Both default recall to 0.7 (irelink) or require it as a parameter (splink).

---

### Default m/u initialisation

**Checked**: Starting values for EM.

**irelink** (il_estimate_em.R:189-191): m = [0.1/(nl-1), ..., 0.9] for
nl levels (high weight on exact match); u = uniform 1/nl.

**splink** (comparison_level.py:72-93): Interpolates m/u from a
log-scale Bayes factor grid (−5 to +10).

**Why correct**: Both are starting points that converge under EM. The
specific initialisation affects iteration count but not the final result.

---

### Infinity handling in scoring

**Checked**: How both packages handle extreme Bayes factors.

**irelink** (utils-sql.R:908): Clamps m and u at `max(x, 1e-10)` before
computing `log2(m/u)`, preventing Infinity weights.

**splink** (predict.py:213): Wraps the combined BF expression in
`LEAST(GREATEST(bf, 1e-300), 1e300)` and adds a CASE for any individual
BF equalling Infinity.

**Why correct**: Both approaches bound the result. irelink's pre-clamping
is simpler; splink's post-clamping with explicit Infinity handling is
more general.

---

### predict include_fields default

**Checked**: Whether original data columns are included in prediction
output by default.

**irelink** (predict.R:93): `include_fields = FALSE` — performance-first
default.

**splink** (predict.py): `retain_matching_columns = True` — includes
fields by default.

**Why not a bug**: Opposite defaults reflecting different API
philosophies. irelink prioritises performance; splink prioritises
convenience. Users should set this explicitly when porting code.
