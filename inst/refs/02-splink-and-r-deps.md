# Splink's Dependencies and Their R Counterparts

This document maps every dependency used by splink to the R packages that
irelink should import (or suggest), and evaluates whether a dbplyr-centred
design can cover the SQL generation needs.

## How splink uses its Python dependencies

### pandas — data frame I/O and post-SQL wrangling

Splink is SQL-first: it pushes computation into the database wherever possible.
Pandas enters the picture for three secondary roles:

1. **Ingestion and export.** Dictionaries and lists are converted to
   DataFrames before being registered as database tables. Query results are
   pulled back as DataFrames for charting or serialisation.
2. **Small-scale analytics.** The EM parameter-update step can fall back to
   pandas (groupby, loc, cumcount) when the result set is small enough.
3. **Data cleaning for visualisation.** Infinity replacement, NaN handling,
   and reshaping (melt, pivot) before feeding data into chart specs.

R has native data frames and tibbles, so no external dependency is needed for
this role. The tidyverse verbs (dplyr, tidyr) are a natural fit for the
small-scale wrangling, though base R alone would suffice.

### sqlglot — SQL parsing, analysis, and dialect translation

Sqlglot is deeply embedded in splink. Its role is frequently misunderstood as
"just a translator" — in reality, splink leans on it for three distinct tasks:

1. **Parsing and structural analysis.** Blocking rules supplied by the user as
   SQL strings are parsed into an AST. Splink inspects the tree to detect
   exact-match conditions, extract equi-join keys vs filter conditions, count
   column references, and decide whether join elimination is possible.
2. **AST transformation.** Utility functions walk the tree to move table
   aliases from prefix position (`l.first_name`) to suffix position
   (`first_name_l`), add table qualifiers to bare column names, simplify and
   normalise conditions, and compute structural signatures for pattern
   matching.
3. **Dialect translation.** After SQL is built as a string (see below), sqlglot
   can re-emit it in another dialect so that the same comparison definition
   works on DuckDB, Spark, SQLite, or Postgres.

However, splink does **not** use sqlglot to *build* SQL from scratch. All query
text is assembled with Python f-strings and string concatenation; sqlglot only
enters the picture after the string already exists. This is an important
distinction: the SQL generation layer is template-based, not AST-based.

### duckdb — default execution backend

DuckDB is the recommended backend and the only one that ships as a hard
dependency. Splink uses the Python DuckDB driver to:

- create in-memory or file-based connections,
- execute SQL via `con.sql()`,
- register pandas DataFrames as named tables,
- convert results back to DataFrames or Parquet/CSV,
- run an optimised EM parameter-update path that avoids the pandas fallback.

DuckDB also provides built-in string-similarity functions (`jaro_winkler`,
`levenshtein`, `damerau_levenshtein`, `jaccard`) that splink's comparison
library calls directly in generated SQL.

### altair — interactive visualisation

Splink ships pre-defined Vega-Lite chart specifications as JSON files (stored
under `internals/files/`). At runtime it loads a spec, injects data, and wraps
it in an Altair `Chart` object for Jupyter rendering. Altair is therefore a
thin envelope; the chart design work is done ahead of time in JSON.

Chart types include match-weight bar charts, M/U parameter displays, waterfall
breakdowns of individual record-pair scores, histograms, comparison-vector
distributions, ROC and precision–recall curves, and interactive cluster and
comparison dashboards.

### Jinja2 — HTML templating for interactive tools

Three features render standalone HTML dashboards: the clerical labelling tool,
the cluster studio, and the comparison viewer. Each has a `.j2` template that
embeds JavaScript (Vega, D3, Observable stdlib) and data payloads. Jinja2 is
used solely for this final rendering step — it does not participate in SQL
generation.

### numpy — lightweight numerics

Numpy is used for a handful of scalar operations (log2, ceil, floor, arange for
histogram bin edges) and for type coercion when serialising database results to
JSON (numpy integers and floats are not natively JSON-serialisable). There is no
matrix algebra or array computing involved.

### igraph — graph clustering

After pairwise match predictions are thresholded, splink builds an undirected
graph of (record-id, record-id) edges and computes connected components to
assign cluster IDs. It also calls `igraph.Graph.bridges()` to identify critical
edges whose removal would disconnect a cluster — a diagnostic aid for cluster
quality. The igraph dependency is optional; if absent, bridge detection is
skipped.

### Optional backend drivers

| Driver | Backend | Role |
|---|---|---|
| pyspark | Apache Spark | `SparkAPI` subclass of `DatabaseAPI` |
| sqlalchemy + psycopg2 | PostgreSQL | `PostgresAPI`, including a user-defined `log2` function |
| awswrangler | AWS Athena | `AthenaAPI`, serverless S3 queries |

Each is a thin adapter that implements the abstract `DatabaseAPI` interface.

---

## How splink generates SQL

This deserves emphasis because it shapes the core architectural decision for
irelink.

Splink assembles SQL **as raw strings**:

- **f-strings** account for roughly 70 % of all SQL generation. Column names,
  table references, Bayes-factor expressions, and CASE clauses are interpolated
  directly.
- **String concatenation and `.join()`** are used to build UNION ALL chains,
  lists of WHEN clauses, and SELECT column lists.
- **`CTEPipeline`** collects individual SQL snippets (each with a logical table
  name) and assembles them into a single `WITH ... SELECT` statement at
  execution time.

Sqlglot never builds a query from an AST. It only touches strings that already
exist — to parse, analyse, transform, or re-emit them in a different dialect.

Representative patterns:

```
Comparison vector:  CASE WHEN ... THEN 2 WHEN ... THEN 1 ELSE 0 END AS gamma_col
Bayes factor:       CASE WHEN gamma_col = 2 THEN cast(5.2 as float8) ... END AS bf_col
Match weight:       log2(least(greatest(cast(prior_bf as float8) * bf1 * bf2, 1e-300), 1e300))
Blocking:           SELECT ... FROM tbl AS l INNER JOIN tbl AS r ON (blocking_rule)
Term frequency:     SELECT col, cast(count(*) as float8) / (SELECT count(col) ...) AS tf_col ...
EM aggregation:     SELECT gamma_col, sum(match_probability * count) AS m_count ... GROUP BY gamma_col
CTE pipeline:       WITH cte1 AS (...), cte2 AS (...) SELECT * FROM cte_final
```

---

## Mapping to R packages

### Core dependencies (Imports)

| Need | R package | Notes |
|---|---|---|
| Database connections | **DBI** | Universal interface: `dbConnect`, `dbGetQuery`, `dbWriteTable`, transactions |
| DuckDB backend | **duckdb** | Default backend; DBI-compliant; built-in `jaro_winkler`, `levenshtein`, `damerau_levenshtein`, `jaccard` |
| Tidy table operations and SQL generation | **dplyr**, **dbplyr** | See dedicated section below |
| SQL string templating | **glue** | Direct analogue of Python f-strings: `glue("SELECT {col} FROM {tbl}")` |
| Graph clustering | **igraph** | Already available in R with identical API: `graph_from_data_frame`, `components`, `bridges` |
| Visualisation | **ggplot2** | Static charts covering match weights, M/U parameters, histograms, waterfall, ROC, PR curves |
| Data wrangling | **tidyr** (maybe) | Pivot and reshape operations for chart data preparation; may be avoidable |
| R6 classes | **R6** (maybe) | If the Linker and settings objects use reference semantics; S3 is also viable |

### Suggested dependencies (Suggests)

| Need | R package | Notes |
|---|---|---|
| Interactive charts | **plotly** or **ggiraph** | Hover, zoom, click for chart interactivity |
| Interactive dashboards | **shiny** | Cluster studio, labelling tool, comparison viewer |
| HTML rendering | **htmltools** | Standalone HTML export for offline charts |
| SQLite backend | **RSQLite** | Lightweight alternative backend |
| PostgreSQL backend | **RPostgres** | Enterprise backend |
| Spark backend | **sparklyr** | Distributed backend |
| String distances in R | **stringdist** | Fallback when the database lacks native similarity functions |

### Dependencies we do *not* need

| Python dep | Why not needed in R |
|---|---|
| pandas | R has native data frames and tibbles |
| numpy | Base R provides `log2`, `ceiling`, `floor`, `seq`; JSON serialisation is not an issue |
| sqlglot | See discussion below — dbplyr handles dialect translation for dplyr pipelines; for raw SQL, we use backend-conditional templates |
| Jinja2 | `glue` covers string interpolation; `htmltools` or `whisker` can render HTML templates |
| altair | `ggplot2` and optionally `plotly` or `shiny` |

---

## Can dbplyr serve as the main entrypoint?

This is the central design question. The short answer is: **dbplyr can and
should be the primary interface for most of the SQL pipeline, with raw DBI
queries as an escape hatch for the parts it cannot express.**

### What dbplyr handles well

dbplyr (v2.5.1, installed on this machine) translates dplyr verbs into
backend-specific SQL. It handles:

- **Joins**, including self-joins with suffix control (`suffix = c("_l", "_r")`).
- **CASE WHEN** via `dplyr::case_when()` and `dplyr::if_else()`.
- **Window functions**: `row_number()`, `rank()`, `dense_rank()`, `lead()`,
  `lag()`, `ntile()`, cumulative aggregates.
- **Aggregations**: `summarise()` with `n()`, `sum()`, `mean()`, `min()`,
  `max()`, `n_distinct()`.
- **CTEs**: `sql_options(cte = TRUE)` forces WITH-clause output instead of
  nested subqueries.
- **Dialect translation**: dbplyr already knows the SQL differences between
  DuckDB, SQLite, PostgreSQL, Spark (via sparklyr), and others. Column quoting,
  function names, type casts, and boolean literals are handled automatically.
- **Raw SQL injection**: `dplyr::sql()` lets you embed an arbitrary SQL
  expression inside a `mutate()` or `filter()`. This is the escape hatch for
  functions dbplyr does not translate natively.

### Where dbplyr needs help

1. **Custom string-similarity functions.** `jaro_winkler()`, `levenshtein()`,
   etc. are not in dplyr's vocabulary. Two approaches:
   - **`sql()` injection**: `mutate(sim = sql("jaro_winkler(first_name_l, first_name_r)"))`.
     Works, but is backend-specific; we would need a thin dispatch layer.
   - **Custom translations**: dbplyr lets packages register new
     translations via `sql_translation()`. irelink could register
     `irl_jaro_winkler()` so that `mutate(sim = irl_jaro_winkler(col_l, col_r))`
     emits the correct SQL for each backend. This is the cleanest path.

2. **Complex CTE pipelines.** Splink chains up to a dozen CTEs in a single
   statement. In dbplyr, each intermediate lazy table acts like a CTE; when
   `sql_options(cte = TRUE)` is active, `show_query()` and `collect()` emit
   WITH clauses. But if the pipeline involves multiple materialised temporary
   tables (not just logical CTEs), we need `DBI::dbExecute()` with
   `compute()` or raw `CREATE TEMP TABLE` statements.

3. **Haversine distance.** No built-in translation. Best handled by a custom
   translation that emits backend-specific SQL or falls back to an R-side
   calculation for small result sets.

4. **Array operations.** DuckDB and Postgres support arrays natively; SQLite
   does not. dbplyr does not expose an array API. Use `sql()` or raw DBI for
   backends that support it, and document the limitation for SQLite.

### Recommended strategy: dbplyr-first with raw-SQL fallback

The following table shows where each pipeline stage should live:

| Pipeline stage | Primary tool | Fallback |
|---|---|---|
| Data registration | `dplyr::copy_to()` / `DBI::dbWriteTable()` | — |
| Blocking (candidate pair generation) | dbplyr joins + filters | Raw SQL for complex custom rules |
| Comparison vector computation | dbplyr `mutate()` + `case_when()` + custom translations | `sql()` injection |
| Term-frequency tables | dbplyr `group_by()` + `summarise()` + `left_join()` | — |
| Bayes factor and match weight | dbplyr `mutate()` with arithmetic | `sql()` for `log2`, `greatest`, `least` if needed |
| EM parameter estimation (SQL part) | dbplyr `group_by()` + `summarise()` | — |
| EM parameter update (R part) | Base R / dplyr on collected tibble | — |
| Prediction thresholding | dbplyr `filter()` | — |
| Clustering | `igraph` on collected edge list | — |
| Visualisation | `ggplot2` on collected tibble | — |

The pattern is: stay in dbplyr (lazy evaluation, backend-agnostic) as long as
possible, collect only when R-side computation is needed (EM updates, graph
clustering, charting), and drop to raw SQL only for backend-specific functions
that lack a dbplyr translation.

---

## Backend coverage matrix

The following table summarises which SQL features are available on each backend
that irelink should target.

| Feature | DuckDB | SQLite | PostgreSQL | Spark |
|---|---|---|---|---|
| Self-join | ✓ | ✓ | ✓ | ✓ |
| CTEs (WITH) | ✓ | ✓ | ✓ | ✓ |
| CASE WHEN | ✓ | ✓ | ✓ | ✓ |
| Window functions | ✓ | ✓ (≥3.25) | ✓ | ✓ |
| `log2()` | ✓ (built-in) | ✗ (needs UDF or `log(x)/log(2)`) | ✗ (needs UDF or `log(x)/log(2)`) | ✓ |
| `greatest()` / `least()` | ✓ | `max()` / `min()` (scalar) | ✓ | ✓ |
| `jaro_winkler()` | ✓ (built-in) | ✗ | ✓ (`fuzzystrmatch` extension) | ✓ |
| `levenshtein()` | ✓ (built-in) | ✗ | ✓ (`fuzzystrmatch` extension) | ✓ |
| `damerau_levenshtein()` | ✓ (built-in) | ✗ | ✗ | ✗ |
| `jaccard()` | ✓ (built-in) | ✗ | ✗ | ✗ |
| Haversine / geo distance | ✗ (expressible as math) | ✗ | ✓ (PostGIS) | ✓ (custom) |
| Array operations | ✓ | ✗ | ✓ | ✓ |
| Temp table creation | ✓ | ✓ | ✓ | ✓ |
| R driver package | `duckdb` | `RSQLite` | `RPostgres` | `sparklyr` |
| dbplyr backend support | ✓ | ✓ | ✓ | ✓ (via sparklyr) |

DuckDB covers the widest range of features out of the box and is the natural
default backend for irelink, just as it is for splink. SQLite is the most
limited but still viable for small jobs that only need exact-match and
numeric comparisons.

---

## Dialect handling without sqlglot

Splink relies on sqlglot to rewrite a single SQL string into the target
dialect. In R, we have two complementary strategies:

1. **Let dbplyr do it.** When the pipeline is expressed as dplyr verbs, dbplyr
   already emits the right SQL for each backend. This covers the majority of
   the pipeline: joins, filters, CASE WHEN, aggregations, window functions,
   arithmetic, and type casts.

2. **Backend-conditional templates for the rest.** For functions that vary by
   backend (string similarities, `log2`, `greatest`/`least`), define a small
   dispatcher that maps a logical function name to the correct SQL fragment.
   This is the natural equivalent of splink's `SplinkDialect` class, which is
   essentially a lookup table of function names per backend.

   ```r
   # Sketch — not final API
   sql_log2 <- function(x, backend) {
     switch(backend,
       duckdb   = glue("log2({x})"),
       sqlite   = glue("(log({x}) / log(2))"),
       postgres = glue("(ln({x}) / ln(2))"),
       spark    = glue("log2({x})")
     )
   }
   ```

   With dbplyr custom translations, this dispatch can be made transparent:
   users write `irl_log2(x)` in a `mutate()` and the translation layer emits
   the right SQL.

---

## Summary of R package dependencies for DESCRIPTION

```
Imports:
    DBI,
    dplyr,
    dbplyr,
    duckdb,
    glue,
    igraph,
    ggplot2,
    rlang
Suggests:
    plotly,
    shiny,
    htmltools,
    RSQLite,
    RPostgres,
    sparklyr,
    stringdist,
    testthat (>= 3.0.0)
```

This list will evolve as implementation proceeds. The `rlang` entry covers
tidy evaluation support that irelink will likely need for non-standard
evaluation in user-facing functions. `R6` may be added if reference semantics
are chosen for the Linker object.
