# 20 — Database Connection Support

## Problem

Prior to this change, all irelink functions required in-memory data frames.
Every call uploaded data via `dbWriteTable()`, which copies the full dataset into the database.
For large data already living in a database, this is wasteful and defeats the purpose of SQL-push-down.

## How splink handles it

splink's `DatabaseAPI` base class provides `_table_registration()` which normalises three input types:

- **pandas DataFrame** — uploaded to the backend with `register_table()`.
- **Table name string** — references an existing table in the catalogue.
- **Dict / Spark DataFrame** — backend-specific materialisation.

All downstream SQL references registered table names, never in-memory objects.
Data stays in the database and is materialised to Python only on explicit `as_pandas_dataframe()`.
See `splink/internals/database_api.py` and backend subclasses.

## R design: `register_data()`

We created an internal helper `register_data()` in `R/utils-register.R` that mirrors splink's approach.
It accepts three input types and normalises them into a database table/view reference:

### Input types

| Input | How it is handled | Copy? |
|-------|-------------------|-------|
| `data.frame` / `tibble` | `dbWriteTable()` — uploaded to DB | Yes (full copy) |
| `tbl_lazy` (dbplyr) | `CREATE VIEW` pointing at source table/query | No (zero-copy) |
| `character` string | `CREATE VIEW` pointing at named table | No (zero-copy) |

### unique_id injection

If the source data lacks a `unique_id` column, the VIEW definition includes
`ROW_NUMBER() OVER () AS unique_id` to generate one automatically.
For data frames, `unique_id` is added as `seq_len(nrow(data))` before upload.

### Connection extraction

When `.data` is a `tbl_lazy`, the DBI connection is extracted via `dbplyr::remote_con()`.
This makes `con` optional in all updated functions.

### Return value

`register_data()` returns a list:

```r
list(
  tbl_name = "__il_data_l",   # internal table/view name

con      = <DBI connection>,   # resolved connection
  n_records = 1000L,          # row count
  columns   = c("first_name", "surname", ...),
  needs_cleanup = TRUE         # whether to drop on exit
)
```

### Cleanup

`drop_registered()` safely removes views or tables:

```r
drop_registered(con, tbl_name)
# Tries DROP VIEW IF EXISTS first, then dbRemoveTable() as fallback
```

This handles the DuckDB quirk where `CREATE OR REPLACE VIEW` fails if an object
of type TABLE already exists with the same name.
We pre-drop before creating views to avoid this.

## Functions updated

| Function | `con` default | Accepts tbl_lazy? | Accepts string? |
|----------|--------------|-------------------|-----------------|
| `il_model()` | `NULL` | ✓ | ✓ |
| `il_attach()` | `NULL` | ✓ | ✓ |
| `il_completeness()` | `NULL` | ✓ | ✓ |
| `il_profile()` | `NULL` | ✓ | ✓ |
| `il_count_pairs()` | `NULL` | ✓ | ✓ |
| `il_deterministic_link()` | `NULL` | ✓ | ✓ |
| `il_largest_blocks()` | `NULL` | ✓ | ✓ |
| `il_find_matches()` | (via model) | ✓ (new_records) | ✓ (new_records) |
| `il_compare_records()` | `NULL` | data.frame only | data.frame only |

`il_compare_records()` keeps data.frame-only inputs since it operates on 1–2 rows.
When `con = NULL`, it creates a temporary DuckDB connection automatically.

## Dependencies

- `dbplyr` added to `Suggests` (only needed for `tbl_lazy` path).
- Checked at runtime via `rlang::check_installed('dbplyr')`.
- No new hard dependencies added.

## Tests

New test file `tests/testthat/test-register-data.R` covers:

- data.frame input path
- Character table name path
- `tbl_lazy` input path
- Table-to-view replacement (DuckDB type conflict regression)
- `il_model()` with `tbl_lazy` input
- `con = NULL` extraction from `tbl_lazy`
- Error on unsupported input type
- Error on zero-row data

All 460+ tests pass, 0 errors / 0 warnings / 0 notes.

## Usage examples

```r
con <- DBI::dbConnect(duckdb::duckdb())

# Path 1: in-memory data frame (existing behaviour)
model <- il_model(my_df, spec = spec, con = con)

# Path 2: dbplyr lazy reference (zero-copy, con extracted automatically)
DBI::dbWriteTable(con, 'patients', patient_data)
tbl_ref <- dplyr::tbl(con, 'patients')
model <- il_model(tbl_ref, spec = spec)

# Path 3: character table name (zero-copy)
model <- il_model('patients', spec = spec, con = con)
```
