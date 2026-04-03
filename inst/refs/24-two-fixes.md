# 24 — Two Gap Fixes

> Closes two remaining weaknesses vs. splink identified in a gap audit
> against the actual package source (not the documentation).
> Both items were carried as known limitations in `22-next-steps.md`.

---

## §1 `include_fields` on the lazy prediction path

### Problem

`predict(model, collect = FALSE)` returns an `il_compared_lazy`
reference that keeps the scored pairs in a database table
(`__il_predicted`).  Before this change, the `include_fields` argument
was silently ignored on the lazy path; the documentation said
"Only applies when `collect = TRUE`."

This was the worst possible combination: `include_fields` is most
valuable for inspecting large datasets — exactly the scenario where
`collect = FALSE` is used.  Users who wanted to browse field values
alongside scores had to collect the full pairs table into R memory,
defeating the purpose of the lazy path.

### Solution

A new internal helper, `build_fields_join_query(model, inner_sql)`
(in `R/utils-sql.R`), wraps any scored-pairs SQL query in two
`LEFT JOIN`s back to the source tables:

```sql
SELECT s.*,
  l.first_name AS first_name_l, l.surname AS surname_l, ...,
  r.first_name AS first_name_r, r.surname AS surname_r, ...
FROM (<scored_query>) AS s
LEFT JOIN <tbl_l> AS l ON s.unique_id_l = l.unique_id
LEFT JOIN <tbl_r> AS r ON s.unique_id_r = r.unique_id
```

`predict_lazy()` now accepts `include_fields` and applies the wrapper
before executing `CREATE TABLE __il_predicted AS ...`.  When
`include_fields = FALSE` (the default), the query is unchanged.

`predict.il_model()` passes `include_fields` through to `predict_lazy()`
on the lazy path.  The `@param include_fields` documentation no longer
restricts the argument to the collected path.

**Files changed:**

| File | Change |
|------|--------|
| `R/utils-sql.R` | Added `build_fields_join_query()` |
| `R/predict.R` | `predict_lazy()` accepts `include_fields`; passed from `predict.il_model()` |

---

## §2 Raw SQL expressions in `il_profile()`

### Problem

`il_profile()` accepted only bare column names (via `rlang::enquos`
and `as.character(rlang::quo_get_expr(q))`).  Splink's
`profile_columns(column_expressions=["city || left(first_name,1)"])` can
profile any SQL expression, which is useful for understanding composite
key distributions before choosing blocking rules.

The workaround — calling `DBI::dbGetQuery()` directly — was awkward
because it bypassed the `top_n` / `bottom_n` filtering, the `il_profile`
S3 class, and the `autoplot()` support.

### Solution

`il_profile()` now inspects each quosure's underlying expression:

- **Symbol or call** (e.g., `first_name`): treated as before —
  quoted with `DBI::dbQuoteIdentifier()` and used as an identifier.
- **Character literal** (e.g., `"city || left(first_name,1)"`): used
  as a raw SQL expression in both the `SELECT` and `GROUP BY` clause.
  The expression string itself becomes the `column` label in the result.

Both forms can be mixed in a single call:

```r
il_profile(df, first_name, "city || left(first_name, 1)", con = con)
```

The raw-expression path is only as safe as the SQL backend allows —
the user controls the expression, so injection is not a concern in
normal use.

**Files changed:**

| File | Change |
|------|--------|
| `R/il_profile.R` | Detects character vs. symbol quosures; uses raw SQL for character inputs |

---

## Tests

Four new tests were added.

**`tests/testthat/test-include-fields.R`** (1 new):

| Test | What it checks |
|------|---------------|
| `include_fields = TRUE` works on lazy path | `collect = FALSE, include_fields = TRUE` creates `__il_predicted` with `_l`/`_r` field columns; `collect_il_compared_lazy()` returns them |

**`tests/testthat/test-il_profile.R`** (2 new):

| Test | What it checks |
|------|---------------|
| Raw SQL expression as character string | `il_profile(df, "first_name || ' ' || city", con = con)` returns rows with the expression as the `column` label |
| Mix of bare names and SQL expressions | Both forms in one call; `column` labels are correct for each |

The new `include_fields` lazy test requires DuckDB (`skip_if_not_installed('duckdb')`).
The new `il_profile` expression tests also require DuckDB because SQLite
does not support the `||` string concatenation natively in the same way.

## Test results

All 646 tests pass (0 failures, 0 warnings, 0 skips).
