# 26 — Splink Parity Polish

> Gap analysis comparing the live splink source against the current
> irelink codebase. Findings from examining splink's comparison library,
> comparison level library, blocking, training, and clustering
> implementations directly. Each gap is assessed for impact and
> actionability.

---

## Methodology

Splink source was read directly at `../splink`. The gap audit in
`18-feature-parity.md` was produced from splink's documentation and
tutorials; this document audits the actual Python source. Key files
examined:

- `splink/internals/comparison_library.py`
- `splink/internals/comparison_level_library.py`
- `splink/internals/comparison_level_composition.py`
- `splink/internals/linker_components/clustering.py`

---

## Gaps

### 1 `cl_dob()` — Hard-coded thresholds

**Splink:** `DateOfBirthComparison` accepts configurable
`datetime_thresholds` and `datetime_metrics` (any combination of
`'day'`, `'month'`, `'year'` values).

**irelink:** `cl_dob()` hard-codes thresholds to 1 month, 1 year, and
10 years.
Users who need different thresholds (e.g., 7 days, 6 months) must build
the comparison manually with `cl_levels()`.

**Fix:** Add `thresholds` and `units` arguments to `cl_dob()`.
The defaults replicate the current behaviour.

**Status:** ✅ Implemented — see implementation log.

---

### 2 `cl_postcode()` — No geographic distance fallback

**Splink:** `PostcodeComparison` accepts optional `lat_col` and `long_col`
arguments and adds `km_thresholds` distance levels as the final fallback
before else, using the Haversine formula in SQL.

**irelink:** `cl_postcode()` and `cl_zip_code()` use substring-prefix
levels only.
There is no geographic distance fallback.

**Fix:** Add optional `lat_col`, `long_col`, and `km_thresholds`
arguments to `cl_postcode()` (and equivalently `cl_zip_code()`).
When supplied, append `cl_distance_km()` levels before `cl_else()`.

**Status:** ✅ Implemented — see implementation log.

---

### 3 `PairwiseStringDistanceFunctionAtThresholds` — No equivalent

**Splink:** Compares the *best-matching pair* of values across two array
columns using any string distance function. Useful when records carry
multiple values for a field (e.g., a list of aliases or alternate
addresses). The SQL computes `MIN(distance)` across the cross-product of
the two arrays.

**irelink:** `cl_array_intersect()` checks whether the arrays share any
common element (exact match) but does not compute pairwise string
distances.

**Fix:** Add `cl_array_min_distance()` — a new comparison level that
generates SQL computing the minimum pairwise string distance (Jaro-Winkler
or Levenshtein) across two array columns.

**Status:** ⬜ Deferred — requires UNNEST cross-join SQL that is
DuckDB-specific and has no clean SQLite fallback.
Users can approximate with `cl_custom()` and explicit UNNEST SQL.

---

### 4 `ArraySubsetLevel` — No built-in level

**Splink:** `ArraySubsetLevel` checks whether one array is a subset of
the other (i.e., every element of the smaller array appears in the
larger one). Handles an `empty_is_subset` flag for null-like empty
arrays.

**irelink:** `cl_array_intersect()` checks that the intersection is
non-empty (shared elements), which is a weaker condition. No subset
check exists.

**Fix:** Add `cl_array_subset()` — generates
`ARRAY_LENGTH(ARRAY_INTERSECT(l.col, r.col)) = LEAST(ARRAY_LENGTH(l.col), ARRAY_LENGTH(r.col))`
SQL for DuckDB. R-side fallback compares sorted sets.

**Status:** ✅ Implemented — see implementation log.

---

### 5 `LiteralMatchLevel` — No built-in level

**Splink:** `LiteralMatchLevel` checks whether a column equals a given
literal value, on the left record, right record, or both. Used to
filter or gate comparison levels on a known value (e.g., both records
must have `country = 'US'`).

**irelink:** No equivalent. Achievable with `cl_custom()`.

**Fix:** Add `cl_literal(value, side)` — a thin wrapper around
`cl_custom()` that generates `l.{col} = 'value'`,
`r.{col} = 'value'`, or `l.{col} = 'value' AND r.{col} = 'value'`.
Works on all backends since it generates plain equality SQL.

**Status:** ✅ Implemented — see implementation log.

---

### 6 `best_link` — No ties handling

**Splink:** `cluster_using_single_best_links` exposes a `ties_method`
parameter: `'drop'` (remove all tied edges) or `'lowest_id'` (keep the
edge to the record with the smallest unique ID).

**irelink:** `il_cluster(method = 'best_link')` keeps one edge per pair
of endpoints but does not expose how ties are resolved.

**Fix:** Add `ties_method = c('lowest_id', 'drop')` to
`il_cluster()`.
`'lowest_id'` (default, matching current behaviour) keeps the edge to
the lower unique ID. `'drop'` removes all tied edges.

**Status:** ✅ Implemented — see implementation log.

---

## Non-gaps (confirmed parity or out of scope)

| Item | Notes |
|------|-------|
| `il_metaphone`/`il_dmetaphone` on DuckDB | Splink also has no SQL-side phonetics on DuckDB; pre-computation required on both |
| Sub-day time differences (`'second'`, `'minute'`, `'hour'`) | Rarely relevant for record linkage; out of scope |
| Interactive dashboards | Explicitly excluded throughout; companion Shiny package recommended |
| Spark backend / salting | Out of scope for R |

---

## Implementation Log

### §1 `cl_dob()` configurable thresholds

`cl_dob()` gains `thresholds` and `units` arguments.
The defaults reproduce the existing behaviour (`thresholds = c(1, 1, 10)`,
`units = c('month', 'year', 'year')`).

Both vectors must be the same length.
Each position pairs one threshold with one unit, passed directly to
`cl_date_diff()`.

```r
# Custom DOB thresholds: within 7 days, 3 months, 2 years
il_spec() |>
  il_compare(dob, cl_dob(thresholds = c(7, 3, 2), units = c('day', 'month', 'year')))
```

**Files changed:**

| File | Change |
|------|--------|
| `R/cl_domain.R` | Added `thresholds` and `units` args to `cl_dob()` |
| `tests/testthat/test-cl-domain.R` | 3 new tests |

**Test count:** 672 passing (4 new: custom thresholds, level count, empty-list error).

---

### §2 `cl_postcode()` geographic distance fallback

`cl_postcode()` and `cl_zip_code()` gain optional `lat_col`, `long_col`,
and `km_thresholds` arguments.
When any of these is provided, `cl_distance_km()` levels are appended
before `cl_else()`.

```r
# UK postcodes with a geographic fallback
il_spec() |>
  il_compare(
    postcode,
    cl_postcode(lat_col = 'lat', long_col = 'lng', km_thresholds = c(1, 10))
  )
```

The distance levels delegate entirely to `cl_distance_km()`, which
already handles the Haversine SQL and unit-tagged thresholds.

**Files changed:**

| File | Change |
|------|--------|
| `R/cl_domain.R` | Added `lat_col`, `long_col`, `km_thresholds` to `cl_postcode()` and `cl_zip_code()` |
| `tests/testthat/test-cl-domain.R` | 3 new tests |

**Test count:** 672 passing (3 new: geo level count, SQL column names, zip geo).

---

### §4 `cl_array_subset()` level

`cl_array_subset()` generates SQL that checks whether the smaller of the
two arrays is a fully contained subset of the larger.

SQL (DuckDB): `ARRAY_LENGTH(ARRAY_INTERSECT(l.col, r.col)) = LEAST(ARRAY_LENGTH(l.col), ARRAY_LENGTH(r.col))`

R-side fallback: converts both values to sets and checks `all(a %in% b) || all(b %in% a)`.

**Files changed:**

| File | Change |
|------|--------|
| `R/cl_array_intersect.R` | Added `cl_array_subset()` |
| `R/utils-sql.R` | Added `'array_subset'` to `sql_sublevel_condition()` and `sql_gamma_case()` |
| `R/utils-em.R` | Added `'array_subset'` to `compute_gamma()` |
| `tests/testthat/test-cl-array.R` | 4 new tests |

**Test count:** 672 passing (2 new: level class, distinct from intersect).

---

### §5 `cl_literal()` level

`cl_literal(value, side)` is a thin wrapper over `cl_custom()`.
`side` controls which record's column is checked: `'both'` (default),
`'left'`, or `'right'`.

```r
# Only compare records where both have country = 'US'
cl_levels(
  cl_null(),
  cl_literal('US', side = 'both'),
  cl_exact(),
  cl_jaro_winkler(0.9),
  cl_else()
)
```

**Files changed:**

| File | Change |
|------|--------|
| `R/cl_custom.R` | Added `cl_literal()` |
| `tests/testthat/test-cl-custom.R` | 3 new tests |

**Test count:** 672 passing (3 new: both-side SQL, left-side SQL, numeric unquoted).

---

### §6 `best_link` ties handling

`il_cluster()` gains `ties_method = c('lowest_id', 'drop')`.

- `'lowest_id'` (default): when two edges tie for best match probability,
  keep the edge to the record with the smaller `unique_id`. This matches
  the previous implicit behaviour.
- `'drop'`: remove all edges involved in a tie.

The SQL path uses a secondary `ORDER BY unique_id_l, unique_id_r` tiebreak
in the `ROW_NUMBER()` window for `'lowest_id'`, or a `HAVING COUNT(*) = 1`
filter for `'drop'`.
The R-side igraph fallback applies the same logic in R.

**Files changed:**

| File | Change |
|------|--------|
| `R/il_cluster.R` | Added `ties_method` parameter; updated SQL and R best_link paths |
| `tests/testthat/test-il_cluster.R` | 3 new tests |

**Test count:** 672 passing (3 new: drop removes tied edges, lowest_id is deterministic, default works).
