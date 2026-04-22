# Deduplication bug: unstable synthetic `unique_id` on lazy inputs

## Summary

The serious stacked pseudopeople failure was **not** a clustering bug and it was
not mainly a threshold-selection bug. The root cause was that, for database-backed
inputs without a `unique_id` column, irelink generated synthetic row IDs with
`ROW_NUMBER() OVER ()` inside a **view**.

On the stacked pseudopeople benchmark, the input is a lazy `UNION ALL` view over
three parquet files. Because the synthetic IDs were not materialized, the same
logical row could receive a different `unique_id` on different queries. That broke
the shared row identity assumed by:

- `predict()`
- `il_accuracy()`
- `il_confusion_matrix()`
- `il_cluster()`
- `il_cluster_confusion_matrix()`

This is what produced the impossible-looking benchmark output where the "best"
threshold was reported near `1`, `predict()` returned `0` pairs, clustering yielded
`0` clusters, but the confusion-matrix helpers still reported nonzero precision and
recall.

## What was wrong

### Synthetic row IDs were generated in a view, not materialized

For `tbl_lazy` and character-table inputs without a user-supplied `unique_id`,
`register_data()` previously created:

```sql
CREATE OR REPLACE VIEW __il_data_l AS
SELECT *, ROW_NUMBER() OVER () AS unique_id
FROM (...)
```

That is unsafe for lazy sources where row order is not fixed. Every later query can
re-evaluate the view and assign different row numbers to the same records.

In the stacked pseudopeople case, this meant evaluation and prediction were often
talking about different records even though they were using the same printed
`unique_id` values.

### Why this showed up so clearly on stacked pseudopeople

The stacked benchmark is built from a lazy SQL view:

- `zero` noise parquet
- `default` noise parquet
- `high` noise parquet

and then passed into `il_model()` without a pre-existing `unique_id`.

That combination made the bug visible:

- the input remained lazy
- row IDs were synthesized in SQL
- the synthetic IDs were reused across many separate benchmark queries

Single-table in-memory examples were much less affected because they either already
had stable row IDs or received `seq_len(nrow(data))` in R before upload.

## Comparison with Splink and fastLink

### Splink

Splink's vertical concatenation path materializes the concatenated data and adds a
`source_dataset` column when multiple inputs are stacked. Its internals explicitly
note that this avoids ID collisions and ambiguity when different inputs may reuse
the same row IDs.

That is the important difference here: Splink does not rely on a re-evaluated view
with fresh `ROW_NUMBER()` assignments for row identity.

### fastLink comparison path

The `fastLink`-style cluster comparison we mirror in
`il_cluster_confusion_matrix()` (`dedupe.ids`-style record-level duplicate flags)
assumes that row identity is stable. Once synthetic row IDs drift between queries,
that comparison becomes meaningless because the predicted clusters and the ground
truth no longer refer to the same records.

## Fix implemented

`register_data()` now **materializes a table** whenever it has to synthesize
`unique_id` for a database-backed input.

So the unsafe pattern:

```sql
CREATE OR REPLACE VIEW ... ROW_NUMBER() OVER ()
```

became a materialized table creation:

```sql
CREATE TABLE ... AS
SELECT *, ROW_NUMBER() OVER () AS unique_id
FROM (...)
```

This fixes the bug by assigning synthetic IDs once, up front, and then reusing the
same stored IDs for prediction, evaluation, and clustering.

## Regression coverage added

- `tests/testthat/test-register-data.R`
  - verifies that synthetic IDs stay stable across repeated reads of a lazy query
    ordered by `random()`
- `tests/testthat/test-il_accuracy.R`
  - verifies that `il_accuracy()` and `il_confusion_matrix()` agree on a lazy input
    without a pre-existing `unique_id`

## Corrected stacked pseudopeople result

Re-running the stacked pseudopeople section after the fix produces a coherent
result:

- best threshold: `0.9928441`
- predicted pairs: `3,029,788`
- pairwise precision / recall / F1: `0.979 / 0.978 / 0.979`
- blocking-miss false negatives: `38,264`
- clusters produced: `1,055,866`
- largest cluster size: `14`
- cluster-level precision / recall / F1: `0.992 / 0.987 / 0.989`

Most importantly, the benchmark no longer collapses to `0` predicted pairs /
`0` clusters, and the pairwise and cluster-level evaluation paths are internally
consistent again.

## Related fixes that still matter

During the same investigation, two additional correctness fixes were made and kept:

1. blocked EM now stores the reversed/global prior back on the model rather than
   the blocking-adjusted prior
2. `cl_null()` levels now produce `gamma = -1` rather than being folded into
   ordinary disagreement

Those were real bugs, but they were not the reason for the later "0 clusters"
benchmark pathology. The zero-cluster symptom was caused by unstable synthetic row
identity on lazy inputs.
