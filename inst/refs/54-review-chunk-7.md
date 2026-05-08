# Chunk 7 review notes

Chunk 7 is now in better shape for human review. The earlier "risks" were
checked one by one; the real defects were fixed, and the remaining items were
reclassified as review notes rather than open bugs.

Main files in scope:

- `R/utils-db.R`
- `R/utils-sql.R`
- `R/il_cleanup.R`

Most relevant neighboring files touched by the fixes:

- `R/utils-register.R`
- `R/utils-tf.R`
- `R/utils-em.R`
- `R/il_estimate_m_from_column.R`
- `R/il_estimate_m_from_labels.R`
- `R/il_comparison_vectors.R`
- `R/utils-evaluation.R`
- `R/il_find_matches.R`
- `R/il_compare_records.R`
- `R/predict.R`

## Final disposition

1. **Issue fixed: SQLite view registration path**

   This was a real bug. `register_data()` used `CREATE OR REPLACE VIEW`, which
   SQLite does not support for these registration paths.

   **Fix:** registration now drops the prior object first and then uses plain
   `CREATE VIEW`. A SQLite-specific `tbl_lazy` regression test was added in
   `tests/testthat/test-register-data.R`.

2. **Issue fixed: identifier quoting in shared SQL and registration helpers**

   This was a real bug. Reserved table names like `select` and non-syntactic
   column names like `first name` could break generated SQL.

   **Fix:** added shared identifier helpers in `R/utils-sql.R` and applied them
   across the active SQL builders and registration code. The fixes cover table
   references, column references, gamma aliases, TF aliases, and related
   lookups. Regression coverage now includes:

- reserved-word source tables in `register_data()`
- quoted blocking SQL for non-syntactic column names
- quoted gamma SQL for non-syntactic column names
- quoted explode helper expectations

3. **Issue fixed: PostgreSQL date/time dialect branching**

   This was a real bug. PostgreSQL `date_diff` SQL was incorrectly using
   `JULIANDAY(...)`, which is SQLite-style SQL.

   **Fix:** added dialect-specific helpers for date and time differences in
   `R/utils-sql.R`, then routed `sql_gamma_case()`,
   `sql_sublevel_condition()`, and `sql_for_comparison_level()` through them.
   Regression coverage now checks that PostgreSQL date-diff SQL uses PostgreSQL
   date arithmetic and does not emit `JULIANDAY`.

4. **Reviewed: backend coverage skew was a test-gap, not a separate code bug**

   The DuckDB-first test setup was real, but the main problem was that it hid
   the confirmed registration and quoting defects.

   **Action taken:** added targeted regressions so the previously missed cases
   are now exercised directly.

5. **Reviewed: lifecycle ownership split was not reproduced as a current bug**

   The split between model-owned cleanup (`il_cleanup()`) and call-scoped
   `on.exit(drop_registered(...))` still looks intentional and internally
   consistent. I did not reproduce a leak or ownership mismatch tied to Chunk 7.

6. **Reviewed: `utils-db.R` remains low risk**

   No defect was reproduced in the SQL profiling wrappers. This part still looks
   like thin instrumentation around DBI calls.

## Efficient human review order

1. Start with the fix points, not the whole chunk:
   `R/utils-sql.R`, `R/utils-register.R`, `R/utils-tf.R`.
2. Then read the callers that prove the quoting changes were carried through:
   `R/utils-em.R`, `R/il_estimate_m_from_column.R`,
   `R/il_estimate_m_from_labels.R`, `R/utils-evaluation.R`, `R/predict.R`.
3. Finish with the regressions:
   `test-register-data.R`, `test-il_block_on.R`, `test-sql-generate.R`,
   `test-explode-blocking.R`, `test-term-frequency.R`.

## What a human reviewer should verify

1. The new helper boundary in `R/utils-sql.R`:
   `sql_quote_identifier()`, `sql_col_ref()`, `sql_identifier_csv()`,
   `sql_date_diff_expr()`, and `sql_time_diff_expr()`.
2. That SQL alias quoting is consistent anywhere `gamma_*` and `tf_*` columns
   are created and then referenced later in the same query pipeline.
3. That `register_data()` now behaves correctly for:
   SQLite lazy-view registration, reserved-word source tables, and object
   replacement after prior registration.

## Bottom line

Chunk 7 no longer has the previously identified concrete blockers:

- SQLite registration syntax bug: fixed
- unquoted identifier bug: fixed
- PostgreSQL date/time SQL bug: fixed

The remaining notes are review guidance, not unresolved defects.
