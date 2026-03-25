# Stage 3 — Test Implementation: Summary

Stage 3 translated splink's Python test suite into irelink's testthat
framework and augmented it with R-specific tests from the implementation
plan. The result is a comprehensive, sprint-gated test suite that served
as the contract for Stage 4 implementation.

## Reference documents

| Document | Contents |
|----------|----------|
| [`10-testing-translation.md`](10-testing-translation.md) | Full translation report: methodology, sprint → file mapping, per-test inventory with splink source traceability |
| [`08-sprints.md`](08-sprints.md) | Sprint definitions that determined test gating |
| [`09-implementation-plan.md`](09-implementation-plan.md) | Stage 3 plan (§3b–3k) and R-specific test targets (§6a–6b) |

## What was built

### Skip-gated test infrastructure

`tests/testthat/setup.R` defines `current_sprint` (an integer) and a
`skip_if_sprint_lt(N)` helper. Every test calls this helper so that
tests for unimplemented sprints are automatically skipped. Incrementing
`current_sprint` progressively un-gates tests as sprints are completed.

See: `10-testing-translation.md`, §1.2–1.3.

### Test suite scope

**27 test files** containing **196 tests** (at time of writing; grew to
334 expectations during Stage 4 as some tests expanded).

| Source | Tests | Notes |
|--------|:-----:|-------|
| Translated from splink | ~180 | Rewritten from class-method to pipe-friendly API |
| R-specific additions | ~14 | From `09-implementation-plan.md` §6a (type safety) and §6b (tidyverse integration) |
| Pipeline integration | 3 | End-to-end workflows spanning multiple sprints |

### Translation methodology

1. **Inventoried** all 68 splink test files (~340+ test functions) across
   17 categories.
2. **Selected** tests covering core features mapped to irelink functions.
   Deferred 66 tests for backend-specific UDFs, caching internals,
   splink2 backward compatibility, salting, and term frequency.
3. **Rewrote** each test from splink's `Linker.method()` pattern to
   irelink's `model |> il_verb()` pipe pattern.
4. **Tagged** every test with its implementation sprint via
   `skip_if_sprint_lt(N)`.

See: `10-testing-translation.md`, §1.1–1.2 and §2.

### Sprint coverage

| Sprint | Focus | Test files | Tests |
|:------:|-------|-----------|:-----:|
| 1 | S3 classes, il_spec, units | 3 files | 20 |
| 2 | cl_* comparison helpers | 3 files | 53 |
| 3 | il_compare, il_block_on | 2 files | 19 |
| 4 | il_demo, string similarity | 2 files | 14 |
| 5 | SQL engine, exploration | 4 files | 20 |
| 6 | il_model, il_cleanup | 1 file | 8+ |
| 7 | Training, weights, parameters | 2 files | 14 |
| 8 | predict, deterministic link, waterfall | 4 files | 11+ |
| 9 | Clustering, graph metrics | 3 files | 11+ |
| 10 | Evaluation, autoplot, save/load | 5 files | 12+ |

See: `10-testing-translation.md`, §2 and §3.

### Test conventions established

- **No loops around expectations.** Each `expect_*()` is a separate,
  traceable assertion — easier to diagnose failures.
- **RSQLite in-memory databases** for all tests, with `withr::defer()`
  cleanup. DuckDB is optional.
- **Demo data** via `il_demo("fake_1000")` — deterministic seed ensures
  reproducibility across sessions.
- **`il_compared` is a tibble subclass**, so standard dplyr verbs
  (`filter`, `select`, `nrow`) work in test assertions.

### What was deferred to Stage 6

Per `09-implementation-plan.md` §6c–6e:

- Snapshot tests for print/summary output (need stable output first)
- Performance benchmarks (need working code to measure)
- Backend compatibility matrix (PostgreSQL, DuckDB vs SQLite)

See: `10-testing-translation.md`, §4 (Deferred to Stage 6).

## Key decisions made during Stage 3

1. **RSQLite as test backend.** DuckDB hangs on this Windows environment;
   RSQLite in-memory is fast and reliable for all unit tests.
2. **Pipeline integration tests span sprints.** `test-pipeline-integration.R`
   contains tests gated at sprints 8, 9, and 10 to verify end-to-end
   workflows as functionality grows.
3. **R-specific tests added.** Type safety tests (zero-row data, factor
   columns, non-spec input) and tidyverse integration tests (dplyr on
   `il_compared`, ggplot2 from `il_weights`) were added beyond splink's
   Python test coverage.

## Package state at end of Stage 3

```
47 R source files (all stubs from Stage 2)
71 exported functions (all stubs)
27 test files, 196 tests (all skip at current_sprint = 0)
0  implemented functions
```
