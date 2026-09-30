# Upstream refresh audit (16 September 2026)

This audit compares `irelink` with the `splink` repository at the current
`master` tip.  It is a maintenance inventory, not a claim of exhaustive
behavioural equivalence.

## Baselines and method

The last substantive `irelink` implementation commit before the refresh is
`8ea2803` (`2026-07-30 12:40 -0400`, “fix + move long to articles”); the
follow-up package/docs commit is `f4ec06a` (`2026-07-30 13:47 -0400`, “minor
fixes”).  The preceding scope-setting commit is `66cc9f7` (`2026-07-29`,
“focus on duckdb and sqlite v1”).  The corresponding upstream ancestry point at
the instant of that last commit is `4e04bdcfd7f09e73eabe33ca5cec6658aeab29d9`
(resolved with `git log --first-parent --before=2026-07-30T17:47:05Z`).
The current upstream tip checked was `ef05e4b89617d5ef4815e58ff1b5aecb6ab07bdc`
(`2026-09-16`, Splink 4.x master).

This is a temporal comparison baseline, not proof of the exact upstream
revision previously ported into irelink: the repositories have independent
histories.  Upstream feature commits often landed through later merge commits;
the table names the feature commit where that gives clearer source evidence.

The comparison used `git diff 4e04bdc..master` and commit/file inspection in
`../splink`; dependency-only bumps and CI churn are recorded as non-runtime
changes.  At the July baseline irelink deliberately supported DBI workflows
through DuckDB and SQLite, with DuckDB SQL as the scalable path and an R-side
SQLite fallback.  That scope remains the governing product boundary.

## Substantive upstream changes and disposition

| Upstream evidence | Change | irelink disposition |
|---|---|---|
| `1b244e99` (2026-07-08) | Spark cosine SQL dialect/comparison support | Python/Spark-only; irelink has no Spark backend. Keep deferred, as documented in ref 58 and the parity matrix. |
| `9ae54384` (2026-07-01) | DuckDB comparison-viewer query speedup | Deferred: irelink's viewer/dashboard is explicitly outside scope; no equivalent runtime path. |
| `3de94a5f`, `6c649754` (2026-07-01) | Small Python comparison-level speedups | Python implementation detail; no translation required. |
| `cb8b0e2a`, `e3eb7dfc` (2026-09-03) | DuckDB profiling redesign, defaults, and error handling | irelink already exposes lightweight `profile_sql` metadata (`il_estimate_u`, prior, predict), but does not implement DuckDB's profiling lifecycle. Review as a future enhancement; do not copy Python internals. |
| `ec0ce354`, `1bc31d39`, `34ea302d` (2026-09-03) | DuckDB registered-prediction source pruning and chunking refactor | Applicable in principle to large lazy predictions. irelink has chunked u-estimation, but no registered-prediction pruning equivalent. High-value performance follow-up requiring benchmarks and correctness tests. |
| `b88f4c65` (2026-09-07) | Parquet-backed DuckDB materialisation and write options | Partially applicable. irelink reads Parquet through optional `nanoparquet`, while internal tables are DBI-created. A future DuckDB-only sink could improve scale but would expand lifecycle/API surface; defer pending a concrete use case. |
| `1b34c683` (2026-09-09) | Comparison-viewer materialisation options and tests | Viewer out of scope; defer. |
| `82870fd2` (2026-09-15), merged by `37bbce56` (2026-09-16) | DateOfBirthComparison uses Levenshtein instead of Damerau-Levenshtein | Applied: `R/cl_domain.R` now uses ordinary `cl_levenshtein(1)` and its focused test asserts the method. |
| `e214b68b` (2026-09-11) | Retire similarity analysis charts | Python chart tooling only. irelink's ggplot data/autoplot API is independent; no port required. |
| `a2b1c70a`, `db2fea26` (2026-09-11) | Altair/Jinja runtime removal and isolated RequireJS contexts | Python docs/dependency architecture; no R dependency or code change. |
| `ca005db0` (2026-09-16) | Make igraph optional | irelink already treats igraph as an optional fallback for SQLite/no-connection clustering (`R/il_cluster.R`); no dependency change needed. Verify DESCRIPTION remains unchanged. |
| `c279d537`, `4e20f049` (2026-09-15) | Formatting/import cleanup | Python-only. |
| `ed6b3b3c` (2026-09-10) | Fellegi–Sunter typo correction (“the the”) | Documentation typo only; no R change required. |

Other first-parent changes after the baseline are notebook rendering, docs
build, release metadata, Spark jars, and dependency updates (DuckDB 1.5.5,
PyArrow 25, sqlglot, SQLAlchemy, etc.). They do not translate into R package
dependencies and should not be added merely for version parity.

For auditability, the first-parent feature merges in this interval are
`72e77f09` (contributing docs, 2026-08-03), `a0e55be9` (Spark cosine,
2026-08-04), `f89da149` (comparison viewer efficiency, 2026-08-04),
`36e58111` (performance docs, 2026-08-05), `bf3587ab` (allow-null-level
documentation, 2026-08-05), `0a3bc998` (Python speedups, 2026-08-05),
`130bbff4` (chunking prefilter, 2026-09-03), `daf03e1b` (DuckDB profiling,
2026-09-03), `41be59ed` (Parquet sink, 2026-09-09), `49a3e960` (retired
similarity charts, 2026-09-16), `aaab630c` (Altair/Jinja dependency removal,
2026-09-16), `85962b3e` (chart docs, 2026-09-16), and `ef05e4b8` (optional
igraph, 2026-09-16). The individual commits in the table are the behavioral
source commits behind those merges.

## Existing parity gaps worth tracking

Some older internal reviews should be read as snapshots rather than current
claims.  In particular, `inst/refs/46-review.md` contains an unverified claim
that Splink lacks `find_matches`, blocking suggestions, and unlinkables.  The
current code and focused tests determine the mappings; irelink's
`il_suggest_blocking()` remains an R-side addition.  Its “85–90%” estimate is
not a measured conformance result and should not be repeated as a project
metric.

The active parity reference (`inst/refs/18-feature-parity.md`) accurately
records Spark, interactive dashboards, salting, and custom profiling
expressions as outside or partial scope.  The DOB algorithm change is now
reflected in code and tests.  The following gaps remain material:

* `il_profile()` accepts column names but not Splink's arbitrary SQL
  `column_expressions`; the documented DBI workaround is appropriate.
* `collect = FALSE` is DuckDB-only in active documentation, while SQLite uses
  the R-side fallback.  Keep this explicit until a tested lazy SQLite path
  exists.
* Splink's registered-prediction source pruning and Parquet materialisation
  have no irelink equivalent; both are scale/performance features, not basic
  model semantics.
* Fixed m/u probability controls are represented differently (`irelink`
  fixes u through its estimation workflow and does not expose every Splink
  setting).  This is an API gap already acknowledged in ref 18.
* Spark-specific comparators and distributed execution remain deferred.  Do
  not describe DBI's generic fallback as Spark support.
* Current irelink intentionally exposes both evidence-only `match_weight` and
  prior-inclusive `total_match_weight`; Splink's naming/semantics differ, and
  the active `from_splink` vignette documents the distinction.  Preserve this
  contract while checking formulas against upstream.
* Inputs are currently one or two datasets (`dedupe`, `link`, or
  `link_and_dedupe`).  Splink's broader multi-source workflows are not
  represented and should be a deliberate future API project.
* irelink intentionally regularises some estimated probabilities and adds
  dependency-aware/custom-prior paths; upstream's raw-proportion paths do not
  automatically map to those extensions.  Treat this as an explicit semantic
  difference and compare formulas in focused tests before changing either
  implementation.

## Recommended update order

1. **Applied in this refresh:** the DOB comparator now uses ordinary
   Levenshtein distance, with regression tests distinguishing transpositions
   from substitutions in both R and DuckDB SQL (`R/cl_domain.R`,
   `tests/testthat/test-cl-domain.R`).
2. **Applied in this refresh:** the DBI profiling wrapper uses the fast path
   when profiling is disabled and preserves profile metadata through lazy
   prediction. Upstream's source-pruning work remains deferred because
   irelink's current direct-table SQL has no demonstrated benefit from it.
3. Decide whether Parquet-backed intermediate tables are needed for an R user
   workflow; if so, design an explicit DuckDB-only option without new package
   dependencies.
4. Keep the parity matrix and active vignettes precise about DuckDB/SQLite
   scope, optional igraph, and deferred Spark/dashboard features.

This file is intentionally dated and evidence-based so a later refresh can
use it as a stable comparison point rather than relying on reflog state.
