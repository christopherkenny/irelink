# 21 — Push Clustering and Graph Metrics into SQL

> **Status: IMPLEMENTED** — SQL-based connected components, graph metrics,
> and best-link filtering are now live for DuckDB/PostgreSQL backends.
> igraph is a fallback (moved to Suggests) for SQLite or no-connection cases.
>
> Original plan for minimising R-side data materialisation in the clustering
> pipeline follows below for reference.
> This document lays out how to push the heavy lifting into SQL,
> following splink's approach, while keeping the R API unchanged.

---

## Current Architecture

### Data Flow

```
predict(model)          →  il_compared tibble (all scored pairs, in R memory)
il_cluster(pairs)       →  igraph connected components (R memory)
il_graph_metrics(pairs) →  R loops over clusters for degree/density
```

### What Gets Pulled Into R

| Step | What | Volume |
|------|------|--------|
| `predict()` | All pairs above threshold | O(edges) rows × (4 + n_comparisons) cols |
| `il_cluster()` | Builds igraph from `pairs` tibble | Already in R — no new pull |
| `il_graph_metrics()` | Iterates `pairs` + `clusters` | Already in R — loop over clusters is O(clusters × edges) |

### Where the Pain Is

The bottleneck is **not** igraph itself (it's O(V+E) and fast). The pain
points are:

1. **`predict()` materialises the full scored-pairs table into R.**
   For a million-record dataset with loose blocking, this can be tens of
   millions of rows × dozens of columns. This is the single largest
   memory allocation in the pipeline.

2. **`il_graph_metrics()` has an O(clusters × edges) R loop** for
   cluster density. The `%in%` membership test inside the loop is
   quadratic in the worst case.

3. **`best_link_filter()` is a scalar R loop** over every edge —
   could be a single SQL window function.

4. **No way to keep results in the database.** After clustering,
   the cluster assignments exist only as an R tibble. Downstream
   SQL joins (e.g., "give me all records in cluster X") require
   re-uploading.

---

## How splink Does It

splink implements connected components as a **pure-SQL iterative
algorithm** based on [Kiveris et al. (2014)](https://arxiv.org/pdf/1802.09478.pdf).
No graph library is used for clustering; igraph is optional and only
used for bridge detection in edge metrics.

### The Algorithm (Representative Propagation)

Conceptually: each node starts as its own representative. On each
iteration, every node adopts the minimum representative among its
neighbours. Repeat until no cross-cluster edges remain.

```
Iteration 0:  {1→1, 2→2, 3→3, 4→4, 5→5}   Edges: 1-2, 2-3, 4-5
Iteration 1:  {1→1, 2→1, 3→1, 4→4, 5→4}   0 cross-cluster edges → done
Result:       Clusters {1,2,3} and {4,5}
```

### SQL Skeleton (per iteration)

```sql
-- Step 1: Propose new representatives (minimum across neighbours)
WITH rep_updates AS (
  SELECT old_rep,
         MIN(representative) AS representative,
         MIN(stable) AS stable
  FROM (
    SELECT node_rep AS old_rep, neighbour_rep AS representative, 0 AS stable
    FROM filtered_neighbours
    UNION ALL
    SELECT representative AS old_rep, representative, 1 AS stable
    FROM prev_representatives
  ) sub
  GROUP BY old_rep
),
-- Step 2: Map back to node_ids
new_representatives AS (
  SELECT prev.node_id, upd.representative, upd.stable
  FROM rep_updates upd
  LEFT JOIN prev_representatives prev
    ON upd.old_rep = prev.representative
)
SELECT * FROM new_representatives
```

After each iteration, splink separates **stable** clusters (all
internal edges) from **unstable** clusters (still have cross-cluster
edges). Only unstable clusters continue to the next iteration. This
gives fast convergence — typically 3–7 iterations even for large graphs.

### Graph Metrics (Pure SQL)

splink computes node degree, centrality, cluster density, and cluster
centralisation entirely in SQL:

```sql
-- Node degree + cluster size (one pass)
SELECT
  c.node_id, c.cluster_id,
  COUNT(*) FILTER (WHERE n.neighbour IS NOT NULL) AS node_degree,
  COUNT(*) OVER (PARTITION BY c.cluster_id)       AS cluster_size
FROM clustered_nodes c
LEFT JOIN all_bidirectional_edges n ON c.node_id = n.node
GROUP BY c.node_id, c.cluster_id

-- Cluster density + centralisation (aggregate of the above)
SELECT
  cluster_id,
  COUNT(*)                AS n_nodes,
  SUM(node_degree) / 2.0 AS n_edges,
  CASE WHEN COUNT(*) > 1
    THEN (2.0 * SUM(node_degree) / 2.0) / (COUNT(*) * (COUNT(*) - 1))
    ELSE NULL END AS density,
  CASE WHEN COUNT(*) > 2
    THEN (1.0 * COUNT(*) * MAX(node_degree) - SUM(node_degree))
       / ((COUNT(*) - 1) * (COUNT(*) - 2))
    ELSE NULL END AS cluster_centralisation
FROM node_metrics
GROUP BY cluster_id
```

### What We Can Learn

| splink pattern | irelink equivalent | Gap |
|---|---|---|
| Edges stay in DB; only cluster IDs returned | Edges pulled to R; igraph runs in-process | **Big** |
| Graph metrics computed in SQL | R loop with `%in%` | **Medium** |
| best-link via SQL `ROW_NUMBER()` window | R scalar loop | **Small** |
| igraph optional (only for bridges) | igraph required (hard dep) | **Design** |
| Multi-threshold: incremental re-clustering | Must re-run from scratch | **Future** |

---

## Proposed Plan

### Phase 1: SQL Connected Components (DuckDB / PostgreSQL)

Create `R/utils-cc.R` implementing splink's iterative representative
propagation entirely in SQL. The R-side driver loop is thin: just fire
SQL statements and check the convergence counter.

**New internal functions:**

```r
# Initialise bidirectional edges + initial representatives
cc_initialise(con, edges_table)

# One iteration: propagate min representative, split stable/unstable
cc_iterate(con, iteration)

# Check convergence: count remaining cross-cluster edges
cc_needs_update(con) -> integer

# Final merge: UNION ALL converged tables → output table
cc_finalise(con) -> character  # returns output table name

# Driver: loops cc_iterate until cc_needs_update returns 0
solve_cc_sql(con, edges_table) -> character  # returns table name
```

**`il_cluster()` changes:**

```r
il_cluster <- function(pairs, threshold = NULL,
                       method = c('connected', 'best_link')) {
  model <- attr(pairs, 'model')
  con <- model$con

  if (!is.null(con) && dialect_has_fuzzy_sql(detect_dialect(con))) {
    # --- SQL path: keep edges in DB, run CC there ---
    upload_edges(con, pairs, threshold)     # write edge list to __il_edges
    if (method == 'best_link')
      sql_best_link_filter(con)             # window-function filter in DB
    tbl <- solve_cc_sql(con, '__il_edges')  # iterative CC → __il_cc_output
    result <- DBI::dbReadTable(con, tbl)    # pull only (node_id, cluster_id)
    return(tibble::as_tibble(result))
  }

  # --- Fallback: current igraph path (SQLite, no connection) ---
  ...existing code...
}
```

**Key design decisions:**

- The edge table uploaded to the DB contains **only** `(unique_id_l,
  unique_id_r)` — no gamma columns, no match_weight. Threshold
  filtering happens during upload (`WHERE match_probability >= ?`).
  This means the upload is minimal.

- For the common case where `predict()` already ran on this connection,
  we can skip the upload entirely and reference the prediction results
  table directly (but this is a Phase 2 optimisation).

- igraph stays as the fallback for SQLite and for users who pass a bare
  tibble without a model attribute. This means igraph can move from
  `Imports` to `Suggests`.

### Phase 2: SQL Graph Metrics

Replace `il_graph_metrics()`'s R loops with SQL queries that match
splink's approach. The SQL path computes everything in one pass (no R
loop over clusters).

**New internal functions in `R/utils-cc.R`:**

```r
# Node degree + cluster size via SQL LEFT JOIN + window
sql_node_metrics(con, cc_table, edges_table) -> character

# Cluster density + centralisation via SQL GROUP BY
sql_cluster_metrics(con, node_metrics_table) -> character
```

**`il_graph_metrics()` changes:**

```r
il_graph_metrics <- function(pairs, clusters) {
  model <- attr(pairs, 'model')
  con <- model$con

  if (!is.null(con) && dialect_has_fuzzy_sql(detect_dialect(con))) {
    # Upload clusters if not already in DB
    # Run SQL node metrics → SQL cluster metrics
    # Pull 3 small result tables
    ...
  }

  # Fallback: current R-side implementation
  ...
}
```

Splink computes density as:
```
density = (2 × n_edges) / (n_nodes × (n_nodes − 1))
```
and centralisation as:
```
centralisation = (n_nodes × max_degree − sum_degree) / ((n_nodes − 1) × (n_nodes − 2))
```

Both are single-pass SQL aggregates — no R loop needed.

### Phase 3: SQL best_link_filter

Replace the R scalar loop with a SQL window function:

```sql
WITH ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY unique_id_l
                       ORDER BY match_probability DESC) AS rank_l,
    ROW_NUMBER() OVER (PARTITION BY unique_id_r
                       ORDER BY match_probability DESC) AS rank_r
  FROM __il_edges
)
SELECT unique_id_l, unique_id_r, match_probability
FROM ranked
WHERE rank_l = 1 AND rank_r = 1
```

This runs in the database and produces the filtered edge list in-place,
avoiding the R loop entirely.

### Phase 4: Move igraph to Suggests

Once Phases 1–3 are complete, igraph is only needed for:
- SQLite fallback (connected components)
- Optional bridge detection (future, like splink)

Change DESCRIPTION from `Imports: igraph` to `Suggests: igraph`, and
gate usage with `rlang::check_installed('igraph')` in the fallback path.

### Phase 5 (Future): Lazy Prediction Pipeline

The biggest win long-term is avoiding the `predict()` materialisation
altogether. Instead of returning a tibble, `predict()` could return a
**lazy reference** to a database table/view containing the scored pairs.
`il_cluster()` would then consume the SQL table directly — zero data
transfer until the user explicitly `collect()`s.

This is a larger API change and should be planned separately. The key
enabler is Phase 1 (SQL CC), which proves that clustering can happen
entirely in-database.

---

## What Changes for Users

**Nothing breaks.** All changes are internal optimisations:

- `il_cluster()` and `il_graph_metrics()` keep their signatures
- Return values are identical tibbles
- When `con` is available (DuckDB/PostgreSQL), SQL path is used
  automatically
- When `con` is NULL or dialect is SQLite, falls back to igraph

The only user-visible change is **performance**: less memory, faster
execution for large datasets.

---

## File Changes Summary

| File | Change |
|------|--------|
| `R/utils-cc.R` | **New.** SQL CC algorithm + graph metrics SQL generators |
| `R/il_cluster.R` | Add SQL path before igraph fallback; SQL best_link |
| `R/il_graph_metrics.R` | Add SQL path before R loop fallback |
| `DESCRIPTION` | Move `igraph` from `Imports` to `Suggests` |
| `tests/testthat/test-il_cluster.R` | Add SQL-path tests; verify identical results vs igraph |
| `tests/testthat/test-il_graph_metrics.R` | Add SQL-path tests |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| SQL CC gives different cluster IDs than igraph | Both produce connected components — IDs differ but partitions are identical. Test with `all.equal()` on the partition, not IDs. |
| Iteration count blows up on pathological graphs | Splink's stable/unstable split bounds iterations to O(diameter). Log iteration count; add max_iterations safety valve. |
| DuckDB temp table proliferation | Clean up `__il_cc_*` tables in `on.exit()` or `il_cleanup()`. |
| Users pass bare tibble (no model attr) | Fall back to igraph path gracefully. |
| `COUNT(*) FILTER (WHERE ...)` not in all dialects | DuckDB and PostgreSQL support it. SQLite doesn't, but SQLite already uses the R fallback. |

---

## Implementation Order

1. **`utils-cc.R`**: Core SQL CC + graph metrics SQL (self-contained, testable)
2. **`il_cluster.R`**: Wire SQL path + SQL best_link
3. **`il_graph_metrics.R`**: Wire SQL metrics path
4. **Tests**: Verify SQL path matches igraph results on known graphs
5. **DESCRIPTION**: Move igraph to Suggests
6. **Cleanup**: `il_cleanup()` drops `__il_cc_*` tables

---

## Appendix: splink's SQL Templates (Reference)

### Bidirectional Edge Initialisation

```sql
SELECT unique_id_l AS node_id, unique_id_l AS node_rep,
       unique_id_r AS neighbour, unique_id_r AS neighbour_rep
FROM edges
UNION ALL
SELECT unique_id_r AS node_id, unique_id_r AS node_rep,
       unique_id_l AS neighbour, unique_id_l AS neighbour_rep
FROM edges
```

### Representative Update (Per Iteration)

```sql
SELECT old_rep,
       MIN(representative) AS representative,
       MIN(stable) AS stable
FROM (
  SELECT node_rep AS old_rep, neighbour_rep AS representative, 0 AS stable
  FROM filtered_neighbours
  UNION ALL
  SELECT representative AS old_rep, representative AS representative, 1 AS stable
  FROM prev_representatives
) sub
GROUP BY old_rep
```

### Cross-Cluster Edge Filter

```sql
SELECT l.representative AS node_rep, n.node_id, n.neighbour,
       r.representative AS neighbour_rep
FROM filtered_neighbours n
LEFT JOIN representatives l ON l.node_id = n.node_id
LEFT JOIN representatives r ON r.node_id = n.neighbour
WHERE l.representative <> r.representative
```

### Convergence Check

```sql
SELECT COUNT(*) AS count FROM filtered_neighbours
```

### Node Degree (SQL)

```sql
SELECT c.node_id, c.cluster_id,
       COUNT(*) FILTER (WHERE n.neighbour IS NOT NULL) AS node_degree,
       COUNT(*) OVER (PARTITION BY c.cluster_id) AS cluster_size
FROM cc_output c
LEFT JOIN bidirectional_edges n ON c.node_id = n.node
GROUP BY c.node_id, c.cluster_id
```

### Cluster Density + Centralisation (SQL)

```sql
SELECT cluster_id,
  COUNT(*)                AS n_nodes,
  SUM(node_degree) / 2.0 AS n_edges,
  CASE WHEN COUNT(*) > 1
    THEN (2.0 * SUM(node_degree) / 2.0) / (COUNT(*) * (COUNT(*) - 1))
    ELSE NULL END AS density,
  CASE WHEN COUNT(*) > 2
    THEN (1.0 * COUNT(*) * MAX(node_degree) - SUM(node_degree))
       / ((COUNT(*) - 1) * (COUNT(*) - 2))
    ELSE NULL END AS cluster_centralisation
FROM node_metrics
GROUP BY cluster_id
```
