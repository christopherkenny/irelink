# Stage 9 — Coverage and Polish (Executive Summary)

## Objective

Close all remaining feature gaps between irelink and splink, push
computation into SQL wherever possible, and bring the package to
production-ready coverage with comprehensive documentation and tests.

## Approach

1. **Deep audit** of all splink source modules against irelink's
   implementation, documented in a 500+ line comparison table
2. **Systematic gap closure** in priority order — high, medium, low —
   with SQL-first implementation throughout
3. **Documentation pass** on pkgdown, NEWS, and roxygen to reflect
   the expanded API surface

## Key Changes

### SQL-native clustering and graph metrics (ref 21)

Replaced R-side igraph connected components with SQL-native iterative
representative propagation for DuckDB and PostgreSQL. igraph remains
as a fallback for SQLite. Graph metrics (`il_graph_metrics()`) compute
node degree, node centrality, cluster density, cluster centralisation,
and bridge detection — all with both SQL and R paths.

*Files:* `R/il_cluster.R`, `R/utils-cc.R`, `R/il_graph_metrics.R`

### Phonetic algorithms (refs 23, 25)

Three phonetic encoding functions — `il_soundex()`, `il_metaphone()`,
`il_dmetaphone()` — usable as both R-side functions and SQL transforms
via `transform = il_soundex`. DuckDB uses native SQL macros; SQLite and
PostgreSQL fall back to R-side computation. `cl_soundex()` provides a
pre-built multi-level comparator.

*Files:* `R/il_phonetic.R`, `R/cl_soundex.R`, `R/utils-sql.R`

### SQL gap fixes (ref 24)

Two targeted fixes: (1) PostgreSQL dialect support for string distance
functions and (2) `il_profile()` SQL expression profiling to match
splink's `column_expressions` argument.

*Files:* `R/utils-sql.R`, `R/il_profile.R`

### Splink parity polish (refs 26–27)

Resolved remaining parity items including `il_suggest_blocking()`,
`il_find_blocking_below()`, `block_from_labels()`, documentation
cleanup, and vignette polish for `from_splink`, `deduplication`,
`record-linkage`, and `advanced` vignettes.

*Files:* `R/il_suggest_blocking.R`, `vignettes/`

### Deep comparison and gap closure (ref 28)

Comprehensive source-level comparison of 146 splink features against
irelink. At audit start: 121 covered, 23 gaps, 12 irelink-original.
After implementation: 135 covered, 5 remaining (4 datasets + 1 config),
19 irelink-original features.

**Gaps resolved (17 items across 7 categories):**

| Category | Items resolved |
|----------|---------------|
| Temporal comparisons | `cl_time_diff()` with `seconds()`, `minutes()`, `hours()` |
| Graph metrics | Bridge detection, node centrality, cluster centralisation |
| Clustering | `source_dataset` for best-link cross-source filtering |
| Scoring | `il_score_missing_edges()`, `threshold_match_weight` on predict |
| Comparison levels | `cl_columns_reversed()` |
| Blocking | `.explode` for array-valued columns (UNNEST) |
| Column expressions | `il_substr()`, `il_regex_extract()`, `il_nullif()`, `il_cast_to_string()`, `il_try_parse_date()`, `il_array_element()` |
| Transform composition | `il_transform()` for multi-function chaining |
| EM training | `max_iterations`, `fix_prior`, `derive_prior`, `estimate_without_tf` |
| Data exploration | `il_comparator_score()`, `il_comparator_threshold_chart()`, `il_phonetic_chart()`, `il_comparison_vectors()` |
| Term frequency | `il_register_tf()` for pre-computed TF tables |
| Visualisation | `il_tf_chart()`, `autoplot.il_string_similarity` |

**New files created:**

- `R/cl_time_diff.R` — sub-day temporal comparison
- `R/cl_columns_reversed.R` — column-swap detection level
- `R/il_transform.R` — multi-function transform composition
- `R/il_column_transforms.R` — 6 SQL column transform factories
- `R/il_comparator_score.R` — batch string similarity + charts
- `R/il_comparison_vectors.R` — gamma pattern distribution
- `R/il_register_tf.R` — pre-computed TF table registration
- `R/il_score_missing_edges.R` — within-cluster pair scoring
- `R/il_tf_chart.R` — TF distribution chart
- `R/utils-unit-helpers.R` — seconds/minutes/hours constructors

## Test Results

860 tests, 0 failures, 0 warnings, 0 skips.

## References

- SQL clustering and graph metrics: `inst/refs/21-clusters.md`
- Next steps roadmap: `inst/refs/22-next-steps.md`
- Phonetic algorithms: `inst/refs/23-phonetics.md`
- SQL gap fixes: `inst/refs/24-sql-process.md`
- SQLite phonetics investigation: `inst/refs/25-phonetics-sqlite.md`
- Splink parity polish: `inst/refs/26-polish.md`
- Documentation and vignette polish: `inst/refs/27-polish.md`
- Deep comparison and gap closure: `inst/refs/28-comparison.md`
