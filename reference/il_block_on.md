# Add a Prediction Blocking Rule

Adds an equality-based blocking rule to a specification. During
prediction, only record pairs that agree on the blocking columns are
scored. Multiple calls are OR-ed together; within a single call, columns
are AND-ed. This mirrors
[`dplyr::join_by()`](https://dplyr.tidyverse.org/reference/join_by.html)
where multiple conditions inside one call are AND-ed.

## Usage

``` r
il_block_on(spec, ..., .where = NULL, .transform = NULL, .explode = NULL)
```

## Arguments

- spec:

  An `il_spec` object (piped in).

- ...:

  \<[`tidy-select`](https://dplyr.tidyverse.org/reference/dplyr_tidy_select.html)\>
  Columns for equality blocking (AND-ed within one call).

- .where:

  An optional raw SQL string for non-equality blocking conditions.
  Defaults to `NULL`.

- .transform:

  An optional transform function applied to both left and right column
  values before the equality check. Useful for phonetic blocking — see
  [il_soundex](http://christophertkenny.com/irelink/reference/phonetic.md),
  [il_metaphone](http://christophertkenny.com/irelink/reference/phonetic.md),
  and
  [il_dmetaphone](http://christophertkenny.com/irelink/reference/phonetic.md).

- .explode:

  An optional character vector of column names containing arrays (list
  columns) to unnest before blocking. Each array element becomes a
  separate row for the blocking join. Requires a DuckDB or PostgreSQL
  backend. Defaults to `NULL`.

## Value

An updated `il_spec` (a new copy; the input is not modified).

## Examples

``` r
# Block on state OR first name (two calls = OR)
spec <- il_spec() |>
  il_block_on(state) |>
  il_block_on(first_name)

# Block where state AND year both match (one call = AND)
spec <- il_spec() |>
  il_block_on(state, year)

# Phonetic blocking: group similar-sounding names
spec <- il_spec() |>
  il_block_on(first_name, .transform = il_soundex)

# Explode array columns before blocking
spec <- il_spec() |>
  il_block_on(email, .explode = 'email')
```
