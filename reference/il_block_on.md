# Add a Prediction Blocking Rule

Adds an equality-based blocking rule to a specification. During
prediction, only record pairs that agree on the blocking columns are
scored. Multiple calls are OR-ed together. Within a single call, columns
are AND-ed.

## Usage

``` r
il_block_on(spec, ..., .where = NULL, .transform = NULL, .explode = NULL)
```

## Arguments

- spec:

  An `il_spec` object (piped in).

- ...:

  Columns for equality blocking (AND-ed within one call). Each entry is
  either:

  - A bare column name, e.g. `surname`.

  - A `column ~ transform` formula, e.g. `first_name ~ il_substr(1, 3)`,
    which applies the transform to that column before the equality
    check. Mix bare names and formulas freely within one call.

- .where:

  An optional raw SQL string for non-equality blocking conditions.
  Defaults to `NULL`.

- .transform:

  An optional transform applied to every column that does not already
  have a formula transform. Can be a single function (e.g.
  [il_soundex](http://christophertkenny.com/irelink/reference/phonetic.md))
  or a named list of functions for per-column transforms. Formula
  transforms in `...` take precedence over `.transform`.

- .explode:

  An optional character vector of column names containing arrays (list
  columns) to unnest before blocking. Each array element becomes a
  separate row for the blocking join. Requires a DuckDB or DuckDB
  backend. Defaults to `NULL`.

## Value

An updated copy of `spec`.

## Examples

``` r
# Block on state OR first name (two calls = OR)
spec <- il_spec() |>
  il_block_on(state) |>
  il_block_on(first_name)

# Block where state AND year both match (one call = AND)
spec <- il_spec() |>
  il_block_on(state, year)

# Per-column substring blocking with formula syntax
spec <- il_spec() |>
  il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))

# Mix: substr on one column, plain match on another
spec <- il_spec() |>
  il_block_on(postcode_fake ~ il_substr(1, 3), dob)

# Same transform on all columns
spec <- il_spec() |>
  il_block_on(first_name, .transform = il_soundex)

# Explode array columns before blocking
spec <- il_spec() |>
  il_block_on(email, .explode = 'email')
```
