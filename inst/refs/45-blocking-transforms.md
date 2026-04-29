# Per-Column Blocking Transforms

## Background

The initial 50k historical-figures vignette used four blocking rules, all
requiring exact matches on two full column values simultaneously:

```r
il_block_on(surname, dob)
il_block_on(first_name, dob)
il_block_on(first_name, surname)
il_block_on(dob, birth_place)
```

The ROC curve for that vignette showed the true-positive rate capping at ~0.45
regardless of threshold. Investigation confirmed the cause: blocking recall was
44.6%. Of 303,961 true match pairs in the data, only 135,496 were ever generated
as candidate pairs. The scoring model never saw the rest, so they were permanent
false negatives.

Sampling the missed pairs showed why: the historical-figures dataset has
pervasive single-field corruption (name typos, corrupted DOBs, missing values).
Many true pairs fail every exact-match blocking rule because they have errors in
all four columns simultaneously:

```
L: davie  braddock  1711-01-01  hart
R: david  braddock  1717-01-01  hart
# first_name differs → misses first_name+dob, first_name+surname
# dob differs        → misses surname+dob, dob+birth_place
```

## Splink Comparison

The splink demo for the same dataset uses ten blocking rules for prediction:

```python
blocking_rules_to_generate_predictions = [
    block_on("substr(first_name,1,3)", "substr(surname,1,4)"),
    block_on("surname", "dob"),
    block_on("first_name", "dob"),
    block_on("postcode_fake", "first_name"),
    block_on("postcode_fake", "surname"),
    block_on("dob", "birth_place"),
    block_on("substr(postcode_fake,1,3)", "dob"),
    block_on("substr(postcode_fake,1,3)", "first_name"),
    block_on("substr(postcode_fake,1,3)", "surname"),
    block_on("substr(first_name,1,2)", "substr(surname,1,2)", "substr(dob,1,4)"),
]
```

Three patterns were missing from our rules:
1. Blocking on `postcode_fake + first_name` / `postcode_fake + surname` (simple
   exact, no transform).
2. Substring blocking: compare only the first N characters of a column.
   This tolerates single-character typos and truncation errors.
3. A combination rule using short substrings across three columns simultaneously,
   which catches pairs that fail every two-column rule.

`il_block_on` already supported a single `.transform` applied uniformly to all
blocked columns (used for phonetic blocking — see `23-phonetics.md`). The
substrate for per-column transforms (`il_substr` and the `is_column_transform`
dispatch in `sql_transform_col`) already existed. The gap was exposing
per-column transforms through the `il_block_on` API.

## Design

### Options considered

**Named list `.transform`** — pass `list(col = transform, ...)` to `.transform`:
```r
il_block_on(first_name, surname,
  .transform = list(first_name = il_substr(1, 3), surname = il_substr(1, 4)))
```
This is programmatically clean but verbose for inline use. Named lists are
idiomatic R but reading a long list literal inside a pipe is not pleasant.

**Formula syntax in `...`** — use `col ~ transform` per argument:
```r
il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
```
The formula LHS is the column name (bare symbol), the RHS is any R expression
that evaluates to a transform closure. Bare symbols work as before. The two
forms compose naturally:
```r
il_block_on(postcode_fake ~ il_substr(1, 3), dob)  # substr on one, plain on other
```

We implemented both. The formula syntax is the primary user-facing API; the
named list `.transform` is kept for programmatic construction (e.g. building
blocking rules from a data frame of column metadata).

### Why `col ~ transform` over `fn(col, ...)` expressions

The natural Python analogy would be `il_substr(first_name, 1, 3)` as a blocking
expression. This requires overloading `il_substr` to detect an unquoted column
name as its first argument and reconstruct a transform closure from the
remaining arguments. That is possible with NSE but relies on knowing the arity
and argument position of every transform function, and breaks if a column
happens to share a name with a transform function argument.

The formula `col ~ transform` is unambiguous: the LHS is always the column
symbol, the RHS is always an ordinary R expression evaluated in the caller's
environment. No transform-function introspection is needed.

### Formula not supported for `il_compare`

`il_compare` uses a different column-transform model (one transform per
comparison, not per blocking rule). Blocking transforms are structurally
different — a blocking rule spans multiple columns and needs an independent
transform decision per column. The formula syntax is therefore specific to
`il_block_on` / `block_on`.

## Implementation

### `parse_blocking_cols`

Internal helper called by both `il_block_on` and `block_on`. Takes a list of
quosures from `...` and returns:
- `columns`: character vector of column names, in order.
- `per_col_tfs`: named list of transforms keyed by column name (only the
  formula columns; bare columns are absent from the list).

Formula detection uses `rlang::is_formula()`. The LHS must be a bare symbol;
the RHS is evaluated in the quosure's enclosing environment. Both sides are
validated with informative errors.

### `merge_blocking_transforms`

Combines `per_col_tfs` from formulas with the explicit `.transform` argument:
- No formulas: return `.transform` as-is (preserves backward compatibility).
- Formulas only, no `.transform`: return the named list directly.
- Both: build a combined list; formula transforms take precedence over
  `.transform` for the overlapping columns.

The merged result is stored in `rule$transform`. `build_blocking_condition`
already handles both a single function and a named list — it looks up
`transform[[col]]` when the transform is a list, falling back to `NULL` (no
transform) for columns absent from the list.

### `build_blocking_condition`

No changes needed beyond what was added for the named-list support. The
per-column dispatch was the only required change:

```r
col_tf <- if (is.list(transform)) transform[[col]] else transform
lcol <- sql_transform_col(glue::glue('l.{col}'), col_tf, dialect)
rcol <- sql_transform_col(glue::glue('r.{col}'), col_tf, dialect)
```

`il_substr(1, 3)` generates `SUBSTRING(col, 1, 3)` via `column_transform_sql`
in `il_column_transforms.R`, which already existed for comparison-level use.

### Validation

`validate_transform_arg` (in `utils-sql.R`) checks that `.transform` is `NULL`,
a single function, or a fully-named list of functions. It is called by both
`il_block_on` and `block_on`.

`parse_blocking_cols` validates that formula LHS is a bare symbol and formula
RHS evaluates to a function, with specific error messages for each failure mode.

### Serialization

Named-list transforms serialize correctly through both code paths:
- **RDS**: the list of closures survives `saveRDS`/`readRDS` intact.
- **JSON (Splink settings)**: `blocking_rule_to_json_settings` calls
  `build_blocking_condition` which expands the transforms into the SQL
  condition string (e.g. `SUBSTRING(l.first_name, 1, 3) = SUBSTRING(r.first_name, 1, 3)`),
  which is what the JSON format stores. Round-trip through JSON loses the R
  transform objects (they become raw SQL in the `where` field after load), but
  that is the existing behavior for all blocking transforms.

### `print.il_spec`

The blocking rule printer shows per-column transform labels when `transform` is
a list. Each column with a transform is rendered as `col [transform_name]`:

```
  Blocking rules (2, OR-ed):
    1. first_name [il_substr(1,3)], surname [il_substr(1,4)]
    2. postcode_fake [il_substr(1,3)], dob
```

## Usage

### Formula syntax (preferred)

```r
spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_dob()) |>
  il_compare(postcode_fake, cl_postcode()) |>
  il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4)) |>
  il_block_on(surname, dob) |>
  il_block_on(first_name, dob) |>
  il_block_on(postcode_fake, first_name) |>
  il_block_on(postcode_fake, surname) |>
  il_block_on(dob, birth_place) |>
  il_block_on(postcode_fake ~ il_substr(1, 3), dob) |>
  il_block_on(postcode_fake ~ il_substr(1, 3), first_name) |>
  il_block_on(postcode_fake ~ il_substr(1, 3), surname) |>
  il_block_on(first_name ~ il_substr(1, 2), surname ~ il_substr(1, 2), dob ~ il_substr(1, 4))
```

Mix bare column names and formula transforms freely within one call. A bare
name means "exact match on the full column value".

### Named list (programmatic)

```r
# Build blocking rules dynamically from metadata
substr_rules <- list(
  first_name = il_substr(1, 3),
  surname    = il_substr(1, 4)
)
spec <- il_spec() |>
  il_block_on(first_name, surname, .transform = substr_rules)
```

### Training-time blocking (`block_on`)

The formula syntax is also available in `block_on()` for EM training and prior
estimation:

```r
model <- il_estimate_em(
  model,
  block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
)
```

## Effect on Blocking Recall

Using the full ten-rule set on the 50k historical-figures data raised blocking
recall from 44.6% to approximately 85–90% (the exact figure depends on model
training and threshold). The ROC TPR ceiling rises accordingly.

The tradeoff is more candidate pairs. The `il_count_pairs` helper lets users
inspect cumulative pair counts before committing to a rule set.

## SQL Generated

For DuckDB, `il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))`
produces a blocking JOIN condition of the form:

```sql
SUBSTRING(l.first_name, 1, 3) = SUBSTRING(r.first_name, 1, 3)
AND SUBSTRING(l.surname, 1, 4) = SUBSTRING(r.surname, 1, 4)
```

For `il_block_on(postcode_fake ~ il_substr(1, 3), dob)`:

```sql
SUBSTRING(l.postcode_fake, 1, 3) = SUBSTRING(r.postcode_fake, 1, 3)
AND l.dob = r.dob
```

`SUBSTRING` is standard SQL and available in DuckDB and PostgreSQL. SQLite
supports `SUBSTR` (same function, different name); the `sql_transform_col`
dispatch currently emits `SUBSTRING` for all dialects, which works in DuckDB
and PostgreSQL. A dialect-specific alias would be needed if SQLite substring
blocking were required.
