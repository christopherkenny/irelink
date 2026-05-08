# Chunk 6 review notes

Chunk 6 covers clustering and graph summaries over scored pairwise edges:
connected components, best-link filtering, one-to-one best-link clustering with
source-dataset constraints, and node/edge/cluster graph metrics.

Main files:

- `R/il_cluster.R`
- `R/il_graph_metrics.R`
- `R/utils-cc.R`

Important neighboring files inspected:

- `R/predict.R`, for the `il_compared` and `il_compared_lazy` objects that feed
  clustering
- `R/il_cluster_confusion_matrix.R`, for a lazy SQL caller that reuses the
  connected-components helpers
- `R/utils-db.R` and `R/utils-sql.R`, for dialect detection, scratch names, and
  table lifecycle conventions
- `inst/refs/34-splink-correctness.md` and
  `inst/refs/35-correctness-audit.md`, for earlier Splink parity notes

Nearby tests:

- `tests/testthat/test-il_cluster.R`
- `tests/testthat/test-il_graph_metrics.R`
- `tests/testthat/test-sql-clustering.R`
- `tests/testthat/test-stage6-plan.R`

## Risk disposition

1. Issue fixed: collected SQL clustering left scratch tables behind.

   Reproduced directly on DuckDB: collected `il_cluster()` left
   `__il_cc_*_edges` and `__il_cc_*_output` tables behind.

   Fix: `cluster_sql()` and `cluster_lazy()` now register the uploaded edge
   table for cleanup with `on.exit(drop_registered(...))`, and both
   `solve_cc_sql()` and `solve_one_to_one_sql()` now drop their output table
   after `collect = TRUE` returns data to R.

   Regression coverage: `test-sql-clustering.R` now checks that no `__il_cc`
   tables remain after connected clustering and after source-constrained
   best-link clustering.

2. Issue fixed: SQL isolated-node cluster IDs were double-prefixed.

   Reproduced directly on the SQL path with thresholded clustering:
   `cluster_cluster_C` appeared for isolated nodes after filtering.

   Fix: isolated nodes are now appended with raw representative IDs, and the
   final `cluster_` prefix is applied exactly once at the end of the SQL
   clustering path.

   Regression coverage: `test-sql-clustering.R` now covers connected and
   source-constrained best-link cases where thresholding removes all edges.

3. Issue fixed: public clustering and graph-metrics validation was too light.

   This was a real issue. `il_cluster()` previously accepted invalid
   thresholds, missing pair columns, and missing `match_probability` on
   best-link paths; `il_graph_metrics()` similarly assumed required columns in
   both `pairs` and `clusters`.

   Fix: `il_cluster()`, `cluster_assignments_lazy_sql()`, and
   `il_graph_metrics()` now validate `threshold`, required pair columns,
   required cluster columns, and malformed cluster-assignment inputs before
   doing any work.

4. Note: SQL/R best-link tie handling did not reproduce as a defect.

   I kept this under review because the iterative SQL ordering expression is not
   obviously the same as the R fallback. A targeted SQL/R parity test with
   source-dataset constraints and reversed tied-edge order now covers the
   reviewed case, and SQL matched the R fallback there.

   Disposition: note, not current issue. Keep an eye on backend-specific
   differences if more complicated tie graphs show up.

5. Issue fixed: `source_dataset` coverage semantics were silently weakening the
   one-record-per-source constraint.

   This was a real issue. Missing mappings were previously treated as
   effectively unconstrained, and duplicate `unique_id` mappings in a data
   frame were silently accepted.

   Chosen contract: if `source_dataset` is supplied, it must cover every
   `unique_id` present in `pairs`, and each `unique_id` may appear only once.

   Fix: `normalise_source_dataset()` now rejects duplicate or missing mappings,
   and both collected and lazy clustering callers validate full coverage before
   best-link clustering starts. The public Rd docs for `il_cluster()` and
   `il_cluster_confusion_matrix()` now say so.

6. Note: core connected-components algorithm still looks okay.

   The SQL algorithm in `utils-cc.R` still matches the earlier correctness
   audit: bidirectional neighbours, min-representative propagation,
   stable/unstable split, cross-cluster edge filtering, and final union of
   stable plus remaining representative tables.

   Remaining human check: decide whether hitting `max_iterations = 100L` should
   warn or error rather than returning the current representative state.

7. Note: graph metric formulas still look okay.

   R and SQL paths compute degree, density, node centrality, and cluster
   centralisation with the expected formulas. Bridge detection intentionally
   remains igraph-based in both SQL and R public paths.

   No correctness bug reproduced here. The new validation only checks input
   shape; it does not change the current contract that metrics are computed
   from the supplied `pairs` graph.

## Review order

1. Start with table lifecycle in `R/il_cluster.R` and `R/utils-cc.R`.

   Check every public SQL clustering route: collected connected, collected
   best-link, collected source-constrained best-link, lazy connected, lazy
   best-link, and `cluster_assignments_lazy_sql()` in Chunk 8. Verify which
   scratch tables should survive and which should be dropped.

2. Review threshold and isolated-node handling.

   Compare collected SQL, lazy SQL, and R/igraph behavior when no edges survive
   thresholding. Confirm the desired output shape and cluster ID convention.

3. Review best-link semantics.

   Check plain mutual-best filtering first, then the iterative one-to-one path.
   Prioritize tie behavior and SQL/R parity over performance questions.

4. Review `source_dataset`.

   Decide the missing-mapping contract, whether data-frame input should reject
   duplicate `unique_id` rows, and whether source-dataset constraints should be
   inferred from `source_dataset_l`/`source_dataset_r` columns when present.

5. Review public validation.

   Add or plan shared validators for edge-list inputs and cluster assignment
   inputs before going deep into more edge cases. This will make later failures
   easier to interpret.

6. Review `il_graph_metrics()`.

   Confirm graph metric formulas, duplicate-edge behavior, bridge behavior when
   igraph is unavailable, and whether cross-cluster edges should be accepted.

## Remaining human-review focus

1. Decide whether hitting `max_iterations = 100L` should warn or error.

2. Decide whether `il_graph_metrics()` should reject cross-cluster edges or
   document the low-level graph-summary contract more explicitly.

## Verification

Focused tests now pass with `devtools::test(filter = 'il_cluster|sql-clustering|il_graph_metrics')`:

- `test-il_cluster.R`
- `test-il_cluster_confusion_matrix.R`
- `test-il_graph_metrics.R`
- `test-sql-clustering.R`
- Result: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 89 ]`

Full package tests now pass with `devtools::test()`:

- Result: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1107 ]`
