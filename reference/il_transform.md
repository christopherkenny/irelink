# Compose Multiple Transforms into a Chain

Creates a single transform function that applies multiple
transformations in sequence — first function applied first, last
function applied last. The result is itself a function that can be
passed as the `transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md).

## Usage

``` r
il_transform(...)
```

## Arguments

- ...:

  Two or more functions to compose, in application order. Each must be a
  recognised transform (e.g. `tolower`, `toupper`, `trimws`,
  [il_soundex](http://christophertkenny.com/irelink/reference/phonetic.md),
  [il_metaphone](http://christophertkenny.com/irelink/reference/phonetic.md),
  [il_dmetaphone](http://christophertkenny.com/irelink/reference/phonetic.md)).

## Value

A function of class `il_transform_chain` that applies all transforms in
order. The individual steps are stored in the `"transforms"` attribute.

## Details

On the SQL side, the transforms are nested inside-out:
`il_transform(tolower, trimws)` becomes `TRIM(LOWER(col))`.

## Examples

``` r
# Lower-case then trim whitespace
tf <- il_transform(tolower, trimws)
tf('  Hello  ')
#> [1] "hello"

# Use in a specification
spec <- il_spec() |>
  il_compare(name, cl_exact(), transform = il_transform(tolower, trimws))
```
