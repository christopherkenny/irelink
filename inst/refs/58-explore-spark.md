# Exploring Spark support

This note evaluates whether `irelink` should support Apache Spark through DBI, most likely via `sparklyr`.
The short answer is that Spark support is feasible and aligned with the package architecture, but it should be treated as a real backend project rather than a free consequence of using DBI.
Spark would not replace DuckDB as the default path.
It would instead give `irelink` a distributed and data-local execution option for very large or institutionally constrained workflows.

## Summary

`irelink` already has the right broad shape for Spark.
It generates SQL, submits that SQL through DBI, keeps large intermediate pair tables in the database, and collects only summaries or final results when needed.
This maps naturally to Spark SQL.

The hard part is SQL dialect and backend behavior.
The current implementation knows about DuckDB, SQLite, and PostgreSQL through `detect_dialect()`.
Most high-performance SQL paths are gated by `dialect_has_fuzzy_sql()`, which currently treats DuckDB and PostgreSQL as the main backends that can compute comparison vectors and predictions in SQL.
Spark would need to be added as a first-class dialect with a capability matrix, not simply classified as `generic`.

Basic Spark support looks achievable.
Full parity with DuckDB and PostgreSQL is harder because Spark SQL does not natively provide every fuzzy string function that `irelink` can use.
In particular, exact matching, numeric differences, date differences, term-frequency adjustment, blocking, aggregation, and Levenshtein-based comparisons fit Spark well.
Jaro, Jaro-Winkler, Damerau-Levenshtein, cosine similarity, and some array or phonetic paths would need either Spark-specific SQL, user-defined functions, or clear unsupported-backend errors.

The most sensible product position is experimental Spark support for a documented subset first.
DuckDB should remain the default and the happy path.
Spark is valuable when the data is already in Spark or when one machine is no longer a realistic execution target.

## What Spark gets us beyond DuckDB

DuckDB is the better default for most users.
It is simple to install, very fast on one machine, excellent with Parquet, and has a SQL feature set that works well for record linkage.
For many linkage jobs, the practical ceiling is not "we need a cluster" but "we need better blocking rules and fewer candidate pairs."

Spark is useful for a different class of problem.
It gets us cluster-scale execution and proximity to enterprise data.
That distinction matters more than raw single-node speed.

Spark is valuable when the data already lives in Spark, Databricks, Hive, or a lakehouse.
In those settings, forcing users to export person-level records to DuckDB may be slow, operationally awkward, or prohibited by governance rules.
Running linkage where the data already lives can be the main benefit.

Spark is also valuable when candidate-pair generation is too large for one machine.
Blocking joins, gamma computation, term-frequency joins, and grouped EM summaries can be distributed across workers.
This does not make bad blocking rules safe, but it does move the upper bound.

Spark also fits production environments where batch jobs are already scheduled through Databricks, EMR, Glue, Spark-on-Kubernetes, or an institutional Spark cluster.
In that world, Spark support is less about analyst convenience and more about deployability.

Spark does not automatically provide better performance than DuckDB.
For small and medium jobs, Spark will usually be slower because of startup, planning, serialization, shuffle, and cluster overhead.
Spark also does not automatically provide better SQL compatibility.
Several fuzzy matching functions that are easy in DuckDB or PostgreSQL are absent from standard Spark SQL.

The right framing is therefore:

| Question | DuckDB | Spark |
|---|---|---|
| Best default backend | Yes | No |
| Simple local analysis | Excellent | Poor to moderate |
| Parquet/lakehouse access | Excellent for many cases | Excellent when data is already in Spark |
| Very large distributed joins | Limited to one node | Strong |
| Enterprise deployment | Possible | Often natural |
| Sensitive data that cannot leave platform | Sometimes difficult | Strong |
| Fuzzy comparator coverage | Strong | Mixed without UDFs |
| Operational complexity | Low | High |

## Current package shape

The DBI design is a good starting point.
The package does not own database connections directly and generally submits SQL through DBI.
That means a `sparklyr` connection could plausibly be passed as `con`, because `sparklyr` exposes Spark through a DBI-compatible connection object.

The important current files are:

- `R/utils-sql.R`, which detects dialects and generates comparison, blocking, gamma, scoring, TF, and greedy SQL.
- `R/utils-register.R`, which normalizes data frames, `tbl_lazy` objects, and table names into backend tables or views.
- `R/predict.R`, which chooses SQL-first prediction for SQL-capable backends and controls lazy prediction with `collect = FALSE`.
- `R/utils-em.R` and `R/il_estimate_em.R`, which compute gamma-pattern counts and run EM.
- `R/il_estimate_u.R`, which samples or counts random pairs for u-estimation.
- `R/utils-cc.R` and `R/il_cluster.R`, which handle SQL-backed clustering and connected-components workflows.

The present dialect detection is intentionally small.
It recognizes DuckDB, SQLite, and PostgreSQL, otherwise returning `generic`.
The high-performance SQL path is currently guarded by a function equivalent to "does this backend have fuzzy SQL support?"
That gate currently excludes Spark.

Adding Spark would begin with:

```r
detect_dialect <- function(con) {
  cls <- tolower(paste(class(con), collapse = " "))
  if (grepl("duckdb", cls)) {
    return("duckdb")
  }
  if (grepl("sqlite", cls)) {
    return("sqlite")
  }
  if (grepl("postgres", cls)) {
    return("postgres")
  }
  if (grepl("spark", cls)) {
    return("spark")
  }
  "generic"
}
```

But the better implementation would also introduce backend capabilities.
Spark should not be treated as identical to DuckDB or PostgreSQL.
It should advertise specific supported operations.

## SQL feature fit

The core linkage workflow has several SQL categories.
Some map cleanly to Spark, while others need work.

### Registration and table lifecycle

Spark can operate through DBI and Spark SQL, but table and view semantics differ from DuckDB.
`irelink` currently creates tables and views with patterns such as `CREATE TABLE ... AS SELECT ...`, `CREATE VIEW ... AS SELECT ...`, `DROP VIEW IF EXISTS ...`, and `dbRemoveTable()`.
These need to be audited against `sparklyr`.

Likely choices:

- Use temp views for many internal registered objects.
- Use managed or temporary tables for materialized intermediates.
- Avoid assuming that `dbRemoveTable()` behaves identically across Spark deployments.
- Be explicit about cleanup behavior and table namespaces.

The existing scratch-table tracking is useful.
It should be extended with Spark-specific table creation and cleanup helpers rather than scattering Spark conditionals across the package.

### Unique IDs

`irelink` can synthesize `unique_id` with `ROW_NUMBER() OVER ()` when input data lacks one.
That is convenient for DuckDB and local databases.
It is riskier in Spark because unordered distributed data may not have stable row order.

For Spark, the safest position is to strongly prefer user-supplied stable `unique_id` columns.
The package can still synthesize IDs for convenience, but documentation should warn that generated IDs are stable only within the materialized registered table and should not be treated as durable identifiers across sessions or source rewrites.

An even stricter experimental Spark backend could require `unique_id` at first.
That would reduce surprise while the backend matures.

### Blocking

Blocking rules are a good Spark fit.
They compile to joins and filters, which Spark is built to distribute.
Equality blocking, transformed equality blocking, and custom SQL blocking should work if the transform SQL is Spark-compatible.

Exploding array blocking rules need Spark-specific syntax.
Spark has array functions and explode support, but the current SQL templates should be checked carefully because DuckDB and Spark use different array idioms.

### Gamma computation

Exact gamma levels are straightforward.
Numeric-difference gamma levels are also mostly straightforward because Spark supports normal arithmetic, casts, `ABS()`, `LEAST()`, and `GREATEST()`.

Date and timestamp comparisons need Spark-specific templates.
Current code uses DuckDB `EPOCH()`, PostgreSQL `EXTRACT(EPOCH FROM ...)`, and SQLite `JULIANDAY()`.
Spark should use Spark SQL functions such as `date_diff`, `unix_timestamp`, or a version-appropriate timestamp-difference function.

Levenshtein comparisons are plausible because Spark SQL provides `levenshtein`.
Soundex is also plausible because Spark SQL provides `soundex`.

Jaro and Jaro-Winkler are the biggest gap.
Spark SQL does not appear to provide standard built-in Jaro or Jaro-Winkler functions.
Because `cl_jaro_winkler()` is central to many record-linkage examples, this is a meaningful limitation.

There are three ways to handle this:

1. Initially mark Jaro and Jaro-Winkler unsupported on Spark.
2. Provide a Spark UDF layer through `sparklyr` or a small JAR.
3. Add an optional approximate or alternative comparator path, such as Levenshtein-heavy specs.

The first path is easiest and honest.
The second path is required for real parity.
The third path may be useful for users whose Spark deployments do not allow custom UDF installation.

### Term frequency

Term-frequency tables should map well to Spark.
They are group-by/count tables joined back to candidate pairs.
This is one of Spark's strengths, provided the joins are planned well.

The main concern is materialization.
The implementation should avoid collecting large TF tables into R.
Only parameter summaries and small diagnostics should be collected.

### EM estimation

The independent EM implementation already has a good shape for Spark.
The expensive work is gamma computation and aggregation into pattern counts.
The actual EM loop can run in R over the compact pattern table.

This should be feasible if the pattern table remains small relative to pairs.
That assumption usually holds because the number of possible gamma patterns is bounded by the product of comparison levels.

Pair-level TF-aware EM is more delicate.
If `estimate_without_tf = FALSE`, per-pair TF variation matters in the E-step.
That can require collecting or iterating over many pair-level rows unless pushed further into SQL.
For Spark, the initial support should probably document that the fast aggregated EM path is preferred.

Dependency-aware scoring and pattern-table EM may also fit Spark because it already works on aggregated patterns.
The key is ensuring that any pattern scoring tables are created with Spark-compatible SQL and not collected at pair scale.

### Prediction

Prediction is a strong candidate for Spark support.
The `collect = FALSE` path is exactly the kind of API Spark wants.
It lets the package score pairs in SQL and return a lightweight reference to a database table rather than pulling millions of rows into R.

The current user-facing text says `collect = FALSE` requires DuckDB or PostgreSQL.
If Spark support is added, that message and the gate should change to a backend-capability check.

The collected path should still work for small outputs.
But Spark documentation should steer users toward `collect = FALSE`, followed by SQL-side clustering, filtering, or export.

### Greedy matching

The SQL greedy matching path is risky.
Current code has DuckDB and PostgreSQL-specific recursive or array-state SQL.
Spark support should probably not start with SQL-side greedy one-to-one matching.

A collected fallback can work for small outputs.
For large Spark outputs, greedy matching should either be marked unsupported or reimplemented as a Spark-specific algorithm.

### Clustering and connected components

Clustering is feasible but needs careful testing.
The current SQL connected-components logic creates iterative intermediate tables.
That style can work in Spark, but performance may depend heavily on shuffles, table persistence, and cleanup.

Spark's distributed nature helps with large edge sets, but connected components are not "free SQL."
For production-scale clustering, a Spark-native graph algorithm might eventually be better.
That would add complexity and probably should not be part of a first Spark milestone.

Initial Spark support could focus on pair generation and scoring.
Clustering can follow once prediction tables are reliable.

## Backend support matrix

A realistic initial support matrix might look like this:

| Feature | Initial Spark support | Notes |
|---|---|---|
| In-memory data upload | Yes | Via `DBI::dbWriteTable()` if supported by `sparklyr`; test carefully. |
| Existing Spark table input | Yes | Likely the most important path. |
| `dbplyr::tbl_lazy` input | Yes | Should work naturally with `sparklyr` and `dbplyr`. |
| Exact comparisons | Yes | Straight SQL. |
| Numeric differences | Yes | Needs Spark-safe casts. |
| Percent differences | Yes | Uses arithmetic and `GREATEST`/`NULLIF` equivalents. |
| Date differences | Yes | Needs Spark-specific SQL. |
| Time differences | Maybe | Needs Spark-version-aware SQL. |
| Levenshtein | Yes | Spark SQL has `levenshtein`. |
| Soundex | Yes | Spark SQL has `soundex`. |
| Jaro | No initially | Needs UDF or unsupported error. |
| Jaro-Winkler | No initially | Needs UDF or unsupported error. |
| Damerau-Levenshtein | No initially | Needs UDF or unsupported error. |
| TF adjustment | Yes | Good Spark fit. |
| EM with aggregated gamma patterns | Yes | Good fit if SQL pattern counts work. |
| Pair-level TF-aware EM | Maybe | Risk of pair-scale collection. |
| `predict(collect = FALSE)` | Yes | Important first-class target. |
| `predict(collect = TRUE)` | Yes for small outputs | Should be discouraged for large jobs. |
| SQL-side greedy matching | No initially | Current SQL is DuckDB/Postgres-specific. |
| SQL-side clustering | Maybe | Needs separate validation and tuning. |

## Implementation plan

The implementation should proceed in stages.
Each stage should leave the package in a coherent state with clear errors for unsupported paths.

### Stage 1: Dialect and capabilities

Add Spark detection to `detect_dialect()`.
Add a backend-capability helper rather than only using `dialect_has_fuzzy_sql()`.
Capabilities should answer questions like:

- Can the backend compute exact comparisons in SQL?
- Can it compute Levenshtein?
- Can it compute Jaro-Winkler?
- Can it create materialized internal tables?
- Can it support lazy prediction?
- Can it support SQL-side greedy matching?
- Can it support SQL-side connected components?

This prevents Spark from being over-promised.
It also improves the current backend architecture for future engines.

### Stage 2: Spark SQL templates

Add Spark branches for SQL functions in `R/utils-sql.R`.
The highest-value templates are:

- Date difference in days.
- Timestamp difference in seconds.
- Array length and intersection.
- Levenshtein.
- Soundex.
- `LEAST`, `GREATEST`, `LOG2`, `EXP`, and casts if any syntax differs.

Unsupported comparison levels should fail early with messages that name the backend and the unavailable function.

### Stage 3: Registration and lifecycle

Create Spark-aware registration helpers.
Test data-frame upload, existing table registration, `tbl_lazy` registration, generated `unique_id`, table cleanup, and model cleanup.

This stage should decide whether Spark uses views, temp views, temporary tables, or normal tables for each internal object type.
The decision should be documented because it affects cleanup and production deployment.

### Stage 4: Core modeling

Test and fix:

- `il_model()`
- `il_estimate_u()`
- `il_estimate_em()`
- `predict(..., collect = FALSE)`
- `predict(..., collect = TRUE)` for small outputs
- term-frequency comparisons

The first passing examples should avoid Jaro-Winkler.
A good initial spec would use exact, date, numeric, Levenshtein, and Soundex comparisons.

### Stage 5: Large-output workflows

Test behavior when output pair tables are too large to collect.
This is the point of Spark support.

The important workflows are:

- Score pairs into a Spark table.
- Count scored pairs without collecting them.
- Filter scored pairs in Spark.
- Join selected fields in Spark.
- Export or leave the result as a Spark table.

### Stage 6: Clustering and advanced features

Only after prediction is reliable should Spark clustering be attempted.
The current connected-components implementation may work with modifications, but it needs careful performance testing.
Greedy one-to-one matching should remain unsupported until a Spark-specific strategy is designed.

## Testing strategy

Spark support should not rely only on unit tests that inspect generated SQL.
It needs integration tests against a local Spark session when available.

Suggested tests:

- Dialect detection recognizes `sparklyr` connections.
- Existing Spark tables can be registered.
- Data frames can be uploaded if the driver supports it.
- `unique_id` is preserved when supplied.
- Exact-only dedupe runs end to end.
- Exact plus numeric/date comparisons run end to end.
- Levenshtein comparison runs end to end.
- Term-frequency adjustment affects match weights.
- `il_estimate_u()` runs without collecting pair-scale data.
- `il_estimate_em()` trains from pattern counts.
- `predict(..., collect = FALSE)` creates a Spark table and returns a lazy reference.
- Unsupported comparators fail before executing expensive jobs.
- Cleanup removes package-created tables or views.

Spark tests should be skipped on CRAN unless a Spark installation is explicitly available.
They can run in CI only if the project chooses to install and manage local Spark there.

## Documentation position

Spark should be documented as optional and experimental at first.
The docs should not imply that all DuckDB examples can simply swap in Spark.

Suggested wording:

> Spark support is intended for workflows where records already live in Spark or where candidate-pair generation exceeds a single-machine backend.
> DuckDB remains the recommended default backend for local analysis and most examples.
> The Spark backend supports a subset of SQL comparison levels initially.
> Unsupported fuzzy comparators raise clear errors unless a Spark UDF extension is installed.

The docs should include a support matrix.
That matrix is more important than a long narrative because users will want to know whether their spec can run.

## Dependency implications

`sparklyr` should be a `Suggests` dependency, not an `Imports` dependency.
Most users should not need Spark installed to use `irelink`.

The package should avoid calling `sparklyr` functions unconditionally.
Any Spark-specific code should use `rlang::check_installed("sparklyr")` or only operate on an existing Spark DBI connection.

If UDF support is added later, it should probably be optional.
That may involve a separate helper, such as `il_register_spark_udfs(con)`, rather than automatic behavior during `il_model()`.

## Risks

The largest technical risk is fuzzy comparator parity.
Jaro-Winkler is common in record linkage examples.
If Spark cannot run it without UDFs, many existing specs will not transfer cleanly.

The largest performance risk is pair explosion.
Spark can distribute large joins, but it cannot rescue an unbounded linkage plan.
The package should continue to emphasize blocking diagnostics and pair counts.

The largest operational risk is table lifecycle.
Spark deployments vary in how they handle temporary views, managed tables, catalogs, permissions, and cleanup.
The backend should avoid surprising users by writing persistent tables unless that behavior is explicit.

The largest correctness risk is unstable generated IDs.
Distributed row order is not a durable identifier.
Spark users should be encouraged or required to provide `unique_id`.

## Feasibility estimate

Basic experimental Spark support is likely a medium-sized project.
The work is mostly dialect and lifecycle engineering rather than model redesign.

Approximate effort:

| Scope | Estimated effort | Description |
|---|---:|---|
| Minimal dialect detection and exact-only smoke path | 1-2 days | Enough to prove a Spark connection can register data and run exact blocking/scoring. |
| Useful experimental backend | 1-2 weeks | Adds Spark SQL templates, tests exact/numeric/date/Levenshtein/TF/EM/lazy prediction, and documents unsupported comparators. |
| Near parity with DuckDB/PostgreSQL | Several weeks | Requires UDF strategy, clustering validation, greedy matching decisions, and large-scale performance testing. |

The recommended first milestone is not full parity.
It is a clearly scoped experimental backend that supports the operations Spark is naturally good at.

## Recommendation

Spark support is worth exploring, but only if it serves a concrete user story:

- The data already lives in Spark or Databricks.
- The records are too large or too restricted to move into DuckDB.
- The desired workflow can tolerate a narrower initial comparator set.
- The output can remain in Spark through `collect = FALSE`.

DuckDB should remain the default backend and the benchmark for user experience.
Spark should be added as an optional scale-out backend with honest capability checks.
That would preserve the simplicity of the package while opening a path for very large administrative linkage workflows.
