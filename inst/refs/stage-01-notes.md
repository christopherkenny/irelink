# Stage 1 — Scope and Structure: Summary

Stage 1 established what splink does, how it does it, and what R tools irelink
will use to replicate it. The two reference documents produced are:

- [`01-what-splink-does.md`](01-what-splink-does.md) — full survey of splink's
  goals, pipeline, architecture, backends, and feature surface.
- [`02-splink-and-r-deps.md`](02-splink-and-r-deps.md) — how each Python
  dependency is used and the corresponding R package mapping.

## What splink is

Splink is a probabilistic record linkage engine built on the Fellegi-Sunter
model. It deduplicates or links records across datasets that lack a shared
identifier, using unsupervised Expectation-Maximisation to estimate model
parameters without labelled training data. The full pipeline runs in seven
stages: configuration → blocking → comparison → training → prediction →
clustering → evaluation. Everything is orchestrated by a central `Linker`
object and executed as SQL against a pluggable database backend.

See: `01-what-splink-does.md`, sections *Overview* through *Architecture*.

## Scale of the translation

The splink internals comprise roughly 68 Python modules plus 5 backend
implementations. The comparison library offers ~20 high-level comparison types
and ~15 lower-level comparison-level conditions. The blocking system supports
exact-match, custom SQL, and composable rules (And, Not, salted, exploding).
Training covers prior estimation, U-parameter sampling, and iterative EM.
Clustering uses igraph connected components. A full visualisation suite
produces interactive Vega-Lite charts.

See: `01-what-splink-does.md`, sections *Comparison system* through
*Visualisation*, and the *Scale of translation* section at the end.

## How splink generates SQL

All SQL is assembled as raw strings via Python f-strings and concatenation —
not through an ORM or AST builder. Sqlglot is used only *after* strings exist,
for parsing, structural analysis, transformation, and dialect re-emission.
Individual SQL snippets are collected into a `CTEPipeline` and flushed as a
single `WITH ... SELECT` statement.

See: `02-splink-and-r-deps.md`, section *How splink generates SQL*.

## R package strategy

**Core dependencies (Imports):** DBI, dplyr, dbplyr, duckdb, glue, igraph,
ggplot2, rlang.

**Suggested dependencies:** plotly or ggiraph, shiny, htmltools, RSQLite,
RPostgres, sparklyr, stringdist, testthat.

See: `02-splink-and-r-deps.md`, section *Mapping to R packages*.

## dbplyr as the main entrypoint

dbplyr can serve as the primary SQL generation layer for most of the pipeline.
Joins, CASE WHEN, window functions, aggregations, and CTEs (via
`sql_options(cte = TRUE)`) are all supported. The main gaps are
backend-specific string-similarity functions, `log2`/`greatest`/`least` on
some engines, and array operations. These are covered by `sql()` injection or
custom dbplyr translations registered by irelink.

Dialect differences that dbplyr does not handle automatically (function name
variations across backends) are managed by a small dispatcher — the R
equivalent of splink's `SplinkDialect` lookup table.

See: `02-splink-and-r-deps.md`, sections *Can dbplyr serve as the main
entrypoint?* and *Dialect handling without sqlglot*.

## Package metadata completed

- **DESCRIPTION** updated with title, description paragraph, and `cph` roles
  for all six splink authors plus the Ministry of Justice.
- **LICENSE / LICENSE.md** amended to include splink's original MIT notice.
- **README.Rmd / README.md** rewritten with a package overview and splink
  attribution.

## Key decisions for Stage 2

The following open questions carry into the planning stage:

1. **Class system.** R6 (reference semantics, closest to Python's Linker) vs
   S3 (idiomatic R, simpler). The Linker holds mutable state (trained
   parameters, cached tables), which favours R6.
2. **Custom dbplyr translations vs raw SQL.** Registering `irl_jaro_winkler()`
   etc. as custom translations is cleaner for users but adds implementation
   complexity. The alternative — `sql()` wrappers — is simpler but
   backend-specific.
3. **Visualisation scope.** Splink ships ~9 chart types. Deciding which to
   include at launch vs defer affects the dependency footprint (ggplot2 alone
   vs ggplot2 + plotly + shiny).
4. **Backend priority.** DuckDB is the default. Which additional backends
   (SQLite, Postgres, Spark) to support in the first release?
