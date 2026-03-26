# Stage 7 — Performance Review (Executive Summary)

## Objective

Profile the irelink package, identify bottlenecks, and implement fixes.
This is the final stage in the implementation roadmap defined in
`inst/notes/goals.md`.

## Approach

1. **Benchmarked** end-to-end pipeline at 200/500/1,000/2,000 records
2. **Profiled** each stage individually (pair generation, gamma, EM, scoring, clustering)
3. **Identified** 1 critical bottleneck, 3 moderate issues, 3 nice-to-haves
4. **Implemented** all critical and moderate fixes
5. **Verified** all 454 tests pass after changes

## Key Findings

### Before Fixes

The pipeline completed in 6.95s for 1,000 records and 15.47s for 2,000.
Two areas dominated runtime:

- **Union-find clustering** scaled as O(n²) due to R's named-vector lookup
  semantics, reaching 88s for 100K edges
- **EM and scoring loops** iterated per-comparison instead of using
  vectorised matrix operations

### Fixes Implemented

| Fix | File | Technique | Impact |
|-----|------|-----------|--------|
| Clustering | `R/il_cluster.R` | igraph::components() | 1,000× at scale |
| Scoring | `R/utils-scoring.R` | Matrix-vector multiply | 8× |
| EM iteration | `R/il_estimate_em.R` | Matrix multiply + crossprod | 8× per iter |
| Find matches | `R/il_find_matches.R` | Batched SQL joins | O(1) DB calls |
| Evaluation | `R/utils-evaluation.R` | Direct pair scoring | Avoids full cross-join |

### After Fixes

| N | Before | After | Speedup |
|---:|-------:|------:|--------:|
| 200 | 1.21s | 0.25s | 4.8× |
| 500 | 2.55s | 0.54s | 4.7× |
| 1,000 | 6.95s | 1.63s | 4.3× |
| 2,000 | 15.47s | 4.36s | 3.6× |

## What Was Not Changed

- **No C code was added.** All speedups came from better R idioms
  (matrix multiply, igraph, batched SQL). C-backed code already exists
  in dependencies (stringdist for string similarity, igraph for graphs,
  BLAS for matrix operations).
- **Pair deduplication** still uses `paste()` + `duplicated()`. Could use
  integer keys at >1M pairs.
- **DB table cleanup** does not use `reg.finalizer()`. Low priority since
  connections are user-managed.

## Remaining Bottleneck

The dominant remaining cost is **SQL pair generation** (cross-joins for
U-estimation, blocked joins for EM/prediction). This is inherent to the
backend and would benefit from DuckDB's columnar engine for larger datasets.

## References

- Detailed report: `inst/refs/15-performance-in-r.md`
- Benchmark scripts: `inst/benchmarks/benchmark.R`, `profile.R`, `profile2.R`, `cluster_scale.R`
- Implementation plan (Stage 7): `inst/refs/09-implementation-plan.md` §7
