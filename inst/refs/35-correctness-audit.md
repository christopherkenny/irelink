# Independent Correctness Audit: irelink vs splink

Direct source-level comparison of irelink (R) and splink (Python,
`../splink`).  Every claim below is based on reading both codebases.
Where `inst/refs/34-splink-correctness.md` made a claim, it was
re-verified from the code; weaknesses in that document are noted inline.

## Summary Table

| investigation | status | risk | irelink path | splink path | evidence | action |
|---|---|---|---|---|---|---|
| TF adjustment NULL handling (SQL path) | **fixed** | high | `R/utils-sql.R:939-969` | `comparison_level.py:594-598` | irelink now uses COALESCE to use whichever TF value exists (matching splink). Previously required BOTH non-NULL. See §1. | done |
| TF adjustment: R-side vs SQL-side inconsistency | **fixed** | high | `R/utils-tf.R:141,153` + `R/utils-sql.R:939-969` | n/a | SQL-side now uses COALESCE matching R-side `pmax(na.rm=TRUE)`. Both paths handle one-sided NULL identically. See §2. | done |
| match_weight prior semantics | intentional | medium | `R/utils-sql.R:1007-1048` | `predict.py:92-115,208-209` | irelink match_weight = Σ log2(m/u) (excludes prior); splink = log2(prior_bf × Π BF). match_probability identical in both. threshold_match_weight not portable. See §3. | document clearly |
| EM M-step regularisation | divergent | medium | `R/il_estimate_em.R:296-324` | `expectation_maximisation.py:44-117` | irelink adds Dirichlet pseudo-counts (0.5/nl) + floor 0.001 + renormalize. splink uses raw proportions. Produces different m/u on same data. See §4. | document; consider making configurable |
| Unobserved gamma levels in EM | divergent | medium | `R/il_estimate_em.R:300-307` | `expectation_maximisation.py:164-210` | irelink: gets ~0.001 from floor + renormalisation. splink: gets string sentinel `LEVEL_NOT_OBSERVED_TEXT`, downstream uses initial value. See §4. | document |
| Percentage diff threshold operator | **fixed** | low | `R/utils-sql.R:290-291` | `comparison_level_library.py:1049` | Changed from `<=` to `<` to match splink. Boundary values now classified the same. | done |
| Scoring formula (match_weight) | correct | none | `R/utils-sql.R:907-915` | `comparison_level.py:565-574` | irelink: Σ log2(m/u) additive. splink: log2(Π m/u) multiplicative. Algebraically identical: log2(Π x) = Σ log2(x). Verified at code level. | none |
| match_probability transform | correct | none | `R/utils-sql.R:1032-1043` | `predict.py:208-218` | irelink: `1/(1+exp(-(log_prior_odds + mw × ln2)))`. splink: `BF/(1+BF)` with Inf guard. Both evaluate to same probability. Verified by expanding irelink's logistic form. | none |
| TF table computation | correct | none | `R/utils-tf.R:28-66` | `term_frequencies.py:33-48` | Both: `COUNT(*) / total_count` on combined (union) data, WHERE col IS NOT NULL. irelink handles link/dedupe separately; splink uses pre-concatenated table. Same values. | none |
| TF adjustment formula (happy path) | correct | none | `R/utils-sql.R:947` | `comparison_level.py:636-638` | irelink: `log2(u/tf) × w` (additive). splink: `POW(u/tf, w)` (multiplicative). Equivalent: `log2(POW(x,w)) = w × log2(x)`. Both select max(tf_l, tf_r) as divisor when both non-NULL. | none |
| TF minimum u floor | correct | none | `R/utils-sql.R:940-942` | `comparison_level.py:618-630` | irelink: `GREATEST(GREATEST(tf_l, tf_r), min)`. splink: 3-arm CASE with explicit comparison. Both ensure divisor ≥ tf_minimum_u_value. When both TF non-NULL, same result. | none |
| Gamma CASE generation | correct | none | `R/utils-sql.R:220-314` | `comparison.py:151-158` | Both: CASE with strictest threshold first, highest gamma to strictest, 0 to ELSE. irelink packs into one CASE; splink assembles per-level. Same output. | none |
| NULL guard on comparisons | correct | none | `R/utils-sql.R:231-232` | `comparison_level_library.py:88-122` | irelink: universal `IS NOT NULL` guard → gamma 0 on NULL. splink: separate NullLevel for gamma -1. irelink lacks gamma -1 but NULLs fall to gamma 0 in both packages when no explicit null level. | none |
| Gamma numbering | correct | none | `R/utils-sql.R:248-250` | `comparison.py:89-106` | Both: highest gamma = strictest level, descending to 0 for ELSE. | none |
| Comparison: exact match | correct | none | `R/utils-sql.R:235-238` | `comparison_level_library.py:286-289` | Both: `l.col = r.col`. | none |
| Comparison: levenshtein | correct | none | `R/utils-sql.R:262-267` | `comparison_level_library.py:420-424` | Both: `levenshtein(l, r) <= threshold`. | none |
| Comparison: jaro_winkler | correct | none | `R/utils-sql.R:246-251` | `comparison_level_library.py:482-486` | Both: `jaro_winkler_similarity(l, r) >= threshold`. | none |
| Comparison: numeric diff | correct | none | `R/utils-sql.R:278-283` | `comparison_level_library.py:1084-1087` | Both: `ABS(l - r) <= threshold`. irelink adds CAST to DOUBLE. | none |
| Comparison: percentage diff | divergent | low | `R/utils-sql.R:286-294` | `comparison_level_library.py:1041-1050` | Operator differs: irelink `<=`, splink `<`. Denominator: irelink `GREATEST(ABS(l),ABS(r))` with NULLIF; splink `CASE WHEN r>l THEN r ELSE l`. Both zero-safe. | fix operator |
| Comparison: date diff | correct | none | `R/utils-sql.R:297-313` | `comparison_level_library.py:830+` | Both: `ABS(date_l - date_r) <= days`. DuckDB: TRY_CAST, SQLite: JULIANDAY. | none |
| Blocking SQL (preceding-rule exclusion) | correct | none | `R/utils-sql.R:550-556` | `blocking.py:151-184` | Both: `AND NOT (COALESCE(rule1, FALSE) OR COALESCE(rule2, FALSE) OR ...)`. Verified line by line: irelink wraps each condition in COALESCE, splink wraps `(blocking_rule_sql)` in coalesce. Same NULL safety. Doc 34 was correct here. | none |
| Blocking dedup (DISTINCT) | correct | none | `R/utils-sql.R:1040-1041` | `blocking.py:637-466` | irelink: SELECT DISTINCT on outer scored query. splink: UNION ALL at blocking, no DISTINCT. Both produce unique pairs. | none |
| EM: aggregated pattern counts | correct | none | `R/utils-em.R:15-62` | `expectation_maximisation.py:27-41` | Both: GROUP BY gamma columns + COUNT. | none |
| EM: E-step formula | correct | none | `R/il_estimate_em.R:233-281` | `predict.py:131-193` | Both: `w = prior × Π m / (prior × Π m + (1-prior) × Π u)`. irelink in log-space with max trick; splink via SQL BF. Equivalent. | none |
| EM: convergence criterion | correct | none | `R/il_estimate_em.R:334-349` | `expectation_maximisation.py:363-427` | Both: max absolute change across m, u, prior. splink skips null levels (gamma -1); irelink has no gamma -1, so both check the same effective level set. | none |
| EM: convergence tolerance default | divergent | low | `R/il_estimate_em.R:87` | `settings_creator.py:33` | irelink: 1e-5. splink: 1e-4. irelink runs more iterations to converge. | document |
| EM: max iterations default | correct | none | `R/il_estimate_em.R:89` | `settings_creator.py:34` | Both: 25. | none |
| EM: blocking-adjusted prior | correct | none | `R/il_estimate_em.R:216-226` | `em_training_session.py:289-320` | Both compute once before EM loop. Both: prior_odds × Π(m_top/u_top) for deactivated columns. irelink clamps result to [1e-6, 1-1e-6]; splink does not clamp. Doc 34 incorrectly stated irelink recomputes per-iteration — it does not (lines 216-226 precede the loop at line 232). | none |
| EM: deactivated columns | correct | none | `R/il_estimate_em.R:128-147,241,298` | `em_training_session.py:99-122` | irelink: skips via `if (deactivated[j]) next` in E-step and M-step. splink: pre-filters comparison list. Same effect. | none |
| EM: prior update | correct | none | `R/il_estimate_em.R:291-293` | `expectation_maximisation.py:72-80` | Both: Σ(match_prob × count) / total_count. irelink clamps to [1e-6, 1-1e-6]; splink unclamped. | none |
| CC: iterative rep propagation | correct | none | `R/utils-cc.R:51-176` | `connected_components.py:168-315` | Both: min-rep propagation from arXiv:1802.09478. Bidirectional edges, MIN(rep, neighbour_reps), stable/unstable split, filter cross-cluster edges, UNION ALL final merge. | none |
| CC: convergence check | correct | none | `R/utils-cc.R:156-159` | `connected_components.py:298-308` | Both: count cross-cluster edges, stop at 0. | none |
| CC: max iterations | divergent | low | `R/utils-cc.R` | `connected_components.py` | irelink: 100 hard limit. splink: no limit (loops until convergence). For finite graphs, both converge. | document |
| Best-link: tie-breaking | correct | none | `R/utils-cc.R:316-317` | `one_to_one_clustering.py:229-234` | irelink: `ROW_NUMBER() OVER (... ORDER BY prob DESC, partner)`. splink: `RANK() OVER (... ORDER BY prob DESC, r.node_id)`. Both break ties by smallest partner ID. ROW_NUMBER and RANK equivalent here because (prob, partner) is unique when partner is a unique ID. | none |
| Best-link: architecture | divergent | low | `R/utils-cc.R:265-338` | `one_to_one_clustering.py:103-338` | irelink: single-pass mutual best-link filter → CC. splink: iterative cluster-aware merging. Both valid for dedupe; splink handles multi-source better. | document |
| estimate_u: floor | divergent | low | `R/il_estimate_u.R:92` | n/a | irelink floors u at 1e-6. splink allows u=0 (risks log(0) downstream). | none (irelink safer) |
| m/u extraction clamping | divergent | low | `R/utils-scoring.R:41-42` | `comparison_level.py:349-357` | irelink: clamps m/u at 1e-10 at extraction (all downstream scoring uses clamped values). splink: does not clamp at extraction; returns Inf when u=0, guards Inf in SQL. Functionally equivalent: both prevent NaN in match_probability. | none |
| Default prior | correct | none | `R/utils-scoring.R:8` | `settings_creator.py:32` | Both: 0.0001. | none |
| prior = 1.0 edge case | fragile | low | `R/utils-scoring.R:90-92` | `predict.py:203-206` | splink: hard-codes BF='Infinity', prob=1.0. irelink: `log(1/(1-1))` = Inf in R. Propagates correctly via IEEE 754: `exp(-Inf)=0`, `1/(1+0)=1`. Works but fragile — depends on Inf arithmetic in SQL engine. | add explicit guard |
| Infinity handling in scoring | correct | none | `R/utils-sql.R:908` | `predict.py:213,217` | irelink: pre-clamps m/u at 1e-10, preventing Inf. splink: LEAST/GREATEST bounds (1e-300 to 1e300) + explicit Infinity CASE. Both prevent NaN. | none |

## Investigation Details

### §1. TF Adjustment NULL Handling (SQL Path)

**What was checked**: The SQL generated when one or both term frequency
values are NULL for a pair.

**irelink** (`sql_tf_adj_expr`, utils-sql.R:952-954):
```sql
CASE WHEN gamma_col = {max_level}
  AND tf_col_l IS NOT NULL AND tf_col_r IS NOT NULL
  AND GREATEST(tf_col_l, tf_col_r) > 0
THEN {log2_u} - LN(GREATEST(tf_col_l, tf_col_r)) / {ln2}
ELSE 0.0 END
```

**splink** (`_tf_adjustment_sql`, comparison_level.py:594-641):
```python
coalesce_l_r = f"coalesce({tf_adj_col.tf_name_l}, {tf_adj_col.tf_name_r})"
coalesce_r_l = f"coalesce({tf_adj_col.tf_name_r}, {tf_adj_col.tf_name_l})"
tf_adjustment_exists = f"{coalesce_l_r} is not null"
# ...
divisor_sql = f"""
(CASE
    WHEN {coalesce_l_r} >= {coalesce_r_l}
    THEN {coalesce_l_r}
    ELSE {coalesce_r_l}
END)
"""
```

**Concrete divergence** — pair where `tf_l = 0.05`, `tf_r = NULL`:

- **splink**: `COALESCE(NULL, 0.05) = 0.05`. `COALESCE(0.05, NULL) = 0.05`.
  Divisor = 0.05. TF adjustment = `POW(u_exact / 0.05, w)`. Applied.
- **irelink SQL**: `tf_r IS NOT NULL` fails → returns 0.0 → no adjustment.

**Impact**: In any linkage task where one dataset has missing values for
a TF-adjusted field, every exact-match pair involving that missing value
receives a different match probability in irelink vs splink. splink's
comment at line 603-608 explicitly explains the COALESCE design: it
protects against one TF being NULL when "the user provided their own
tf adjustment table that didn't contain some of the values in this data."

**Doc 34 assessment**: Investigation "TF adjustment SQL" (row 14) stated
"Equivalent" with no risk. It verified the formula but did not check the
guard clauses. The COALESCE vs IS NOT NULL difference is in the SQL that
wraps the formula, not in the formula itself.

**Fix applied**: `sql_tf_adj_expr` now uses `COALESCE(tf_col_l, tf_col_r)`
and `COALESCE(tf_col_r, tf_col_l)` for the divisor, and checks
`COALESCE(tf_col_l, tf_col_r) IS NOT NULL` (at least one side exists).
This matches splink's semantics. Tests added.

---

### §2. TF Adjustment: R-side vs SQL-side Inconsistency

**What was checked**: Whether irelink's R-side fallback path (used for
SQLite) produces the same TF adjustment as the SQL path (used for
DuckDB/PostgreSQL).

**R-side** (`compute_tf_adjustment`, utils-tf.R:141,153):
```r
tf_max <- pmax(tf_l, tf_r, na.rm = TRUE)
mask <- gamma_mat[, j] == max_level & !is.na(tf_max) & tf_max > 0
```

`pmax(0.05, NA, na.rm = TRUE)` returns `0.05`. The adjustment is applied
using the available value.

**SQL-side** (`sql_tf_adj_expr`, utils-sql.R:952-954):
```sql
AND tf_col_l IS NOT NULL AND tf_col_r IS NOT NULL
```

Requires **both** values to be non-NULL. Returns 0.0 if either is NULL.

**Impact**: The same irelink model, on the same data, produces different
match weights depending on whether `collect = TRUE` with a DuckDB
backend (SQL path) or a SQLite backend (R-side path). This is an
internal inconsistency within irelink. The R-side behaviour is closer
to splink's COALESCE semantics.

**Doc 34 assessment**: Not investigated. Doc 34 does not mention the
R-side fallback path at all.

**Fix applied**: The SQL-side now uses COALESCE (same as §1), which
aligns it with the R-side `pmax(na.rm=TRUE)` behaviour. Both paths
now handle one-sided NULL by using the available value.

---

### §3. match_weight Prior Semantics

**What was checked**: Whether the `match_weight` column in prediction
output means the same thing in both packages.

**irelink** (utils-sql.R:1007-1048):
```r
all_weight_parts <- c(weight_parts, tf_parts)
weight_expr <- paste(all_weight_parts, collapse = ' + ')
# match_weight = Σ log2(m_j/u_j) + Σ tf_adj_j
```

The prior is not included. It enters only in the match_probability:
```r
log_prior_odds <- log(prior / (1 - prior))
# 1.0 / (1.0 + EXP(-(log_prior_odds + match_weight * ln2)))
```

**splink** (predict.py:92-115, 208-209):
```python
bf_prior = prob_to_bayes_factor(prior)  # prior / (1-prior)
bf_expr = f"cast({bf_prior} as float8) * " + " * ".join(bf_terms)
# match_weight = log2(bf_prior × Π BF_j × Π TF_adj_j)
```

The prior IS included in match_weight.

**Numerical difference**: With default prior = 0.0001:
`log2(0.0001 / 0.9999) ≈ -13.29`. So irelink's match_weight is
~13.29 higher than splink's for the same pair.

**match_probability**: Both are identical — verified by expanding
irelink's logistic form:
```
1/(1+exp(-(ln(p/(1-p)) + mw·ln2)))
= 1/(1+exp(-ln(p/(1-p)))·exp(-mw·ln2))
= 1/(1 + (1-p)/p · 1/2^mw)
= p·2^mw / (p·2^mw + (1-p))
= (p·Π(m/u)) / (p·Π(m/u) + (1-p))
```
which is the same as splink's `BF/(1+BF)`.

**Action**: This is a deliberate design choice (Fellegi-Sunter pure
evidence weight vs prior-inclusive weight), but `threshold_match_weight`
values are **not portable** between packages. Must be documented.

---

### §4. EM M-step Regularisation

**What was checked**: How m and u parameters are updated from weighted
counts in the maximisation step.

**irelink** (il_estimate_em.R:296-324):
```r
for (k in seq(0L, nl - 1L)) {
  mask <- pattern_mat[, j] == k
  raw[k + 1L] <- (sum(weights[mask] * pattern_n[mask]) + 0.5 / nl) / (sum_w + 0.5)
}
raw <- pmax(raw, 0.001)
raw <- raw / sum(raw)
```

Three-stage regularisation:
1. **Dirichlet pseudo-count**: adds `0.5/nl` to each level's numerator,
   `0.5` to the denominator
2. **Floor**: clamp each probability to at least 0.001
3. **Renormalize**: ensure probabilities sum to 1

**splink** (expectation_maximisation.py:88-117):
```sql
m_count / sum(m_count) OVER (PARTITION BY output_column_name) as m_probability
```

Pure empirical proportions. No smoothing, no floor. If a level is never
observed in the data, `populate_m_u_from_lookup` (line 178) sets the
probability to `LEVEL_NOT_OBSERVED_TEXT` (a string sentinel), and the
parameter retains its initial value.

**Impact**: On sparse data with levels that have very few observations,
irelink's regularisation pulls parameters toward the prior (uniform for
the pseudo-count) and prevents any parameter from reaching zero. splink
allows parameters to reach zero, which can cause `log(0)` in subsequent
E-steps — though in practice, splink's initialisation and the EM
structure make this rare.

On well-populated data, the difference is negligible because the
pseudo-counts (0.5/nl ≈ 0.25 for a 2-level comparison) are small
relative to the data counts.

**Doc 34 assessment**: Correctly identified this as a difference
(row 36) but marked risk "low" with no action. Did not quantify the
effect on final parameters or match probabilities. For sparse training
data, the effect can be significant.

---

### §5. Blocking-Adjusted Prior Timing

**What was checked**: Whether the blocking-adjusted prior is computed
once or updated per EM iteration.

**irelink** (il_estimate_em.R:216-226):
```r
if (any(deactivated)) {
  prior_bf <- prior / (1 - prior)
  for (j in which(deactivated)) {
    nl <- levels_per_comp[j]
    m_top <- m_list[[j]][nl]
    u_top <- u_list[[j]][nl]
    level_bf <- max(m_top, 1e-10) / max(u_top, 1e-10)
    prior_bf <- prior_bf * level_bf
  }
  prior <- min(max(prior_bf / (1 + prior_bf), 1e-6), 1 - 1e-6)
}
```

This code is at lines 216-226, **before** the EM loop at line 232.
It executes once.

**splink** (em_training_session.py:123-124):
```python
core_model_settings.probability_two_random_records_match = (
    self._blocking_adjusted_probability_two_random_records_match
)
```

Also computed once in `__init__`, before the EM loop.

**Both compute the adjusted prior once using initial m/u.** This is
equivalent behaviour.

**Doc 34 assessment**: Investigation "EM: blocking-adjusted prior"
(row 40) stated: "irelink's per-iteration recalculation is slightly more
accurate." This is wrong — irelink does not recalculate per-iteration.
The code at lines 216-226 precedes the loop. Doc 34 misread the code
structure.

---

### §6. Percentage Diff Threshold Operator

**What was checked**: The comparison operator used for percentage
difference thresholds.

**irelink** (utils-sql.R:290-291):
```r
'WHEN {null_guard} AND ABS(CAST({lcol} AS DOUBLE) - CAST({rcol} AS DOUBLE)) /
NULLIF(GREATEST(ABS(CAST({lcol} AS DOUBLE)), ABS(CAST({rcol} AS DOUBLE))), 0)
<= {thresholds[i]} THEN {n - i + 1L}'
```

Uses `<=` (less than or equal).

**splink** (comparison_level_library.py:1044-1049):
```python
f"(ABS({col.name_l} - {col.name_r}) / "
f"(CASE "
f"WHEN {col.name_r} > {col.name_l} THEN {col.name_r} "
f"ELSE {col.name_l} "
f"END)) < {self.percentage_threshold}"
```

Uses `<` (strict less than).

**Impact**: A pair whose percentage difference is exactly at the
threshold boundary will be classified as matching in irelink but not in
splink. This affects only boundary cases and the probability of an
exact boundary hit is low in practice, but it is a real semantic
difference.

**Doc 34 assessment**: Investigation "percentage diff" (row 30) stated
"correct" with no risk. It checked the formula structure but not the
comparison operator.

**Fix applied**: Changed `<=` to `<` on line 291. Test added verifying
the generated SQL uses strict `<`.

---

### §7. What Remains Uncertain

The following areas were not fully verified and represent residual risk:

1. **Combined effect of EM differences.** The regularisation, tolerance,
   u-floor, and prior-clamping differences were each identified, but
   their combined effect on final match probabilities has not been
   measured on real data. Running both packages on the same dataset
   with identical configurations would quantify this.

2. **Multi-dataset (link_and_dedupe) edge cases.** Both packages support
   link_and_dedupe mode with three table-pair combinations. The table-pair
   generation logic was reviewed (`build_table_pairs` in irelink,
   `_sql_gen_where_condition` in splink) and appears equivalent, but was
   not tested with actual multi-dataset inputs.

3. **PostgreSQL dialect.** All SQL verification was against DuckDB
   semantics. PostgreSQL-specific behaviour (GREATEST NULL handling,
   type coercion) was not tested.

4. **Splink per-level TF configuration.** Splink allows TF adjustment
   on any comparison level (not just exact match). irelink only applies
   TF at `gamma == max_level`. If a splink model configures TF on a
   non-exact-match level, the configurations are not equivalent. In
   standard usage (TF on exact match only), this does not matter.
