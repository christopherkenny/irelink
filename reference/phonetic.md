# Phonetic Transform Functions

Phonetic algorithms for blocking and comparison transforms. These
functions compute phonetic encodings that group similar-sounding names
together. They are useful for blocking rules that tolerate spelling
variation.

## Usage

``` r
il_soundex(x)

il_metaphone(x)

il_dmetaphone(x)
```

## Arguments

- x:

  A character vector to encode.

## Value

A character vector of phonetic codes (same length as `x`).

## Details

When used as a `transform` argument in
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
[`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md),
or
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md),
the computation is pushed into SQL so data is never materialized into R.

### SQL availability

|                 |             |                           |
|-----------------|-------------|---------------------------|
| Function        | DuckDB      | SQLite                    |
| `il_soundex`    | yes (macro) | comparisons only (R-side) |
| `il_metaphone`  | no          | no                        |
| `il_dmetaphone` | no          | no                        |

SQLite does not expose a way to register scalar R functions as SQL UDFs,
so phonetic transforms cannot be used in **blocking rules** on SQLite.
They continue to work in **comparisons** on SQLite via the R-side gamma
computation path.

## Examples

``` r
il_soundex(c('Smith', 'Smyth'))
#> [1] "S530" "S530"
il_soundex(c('Robert', 'Rupert'))
#> [1] "R163" "R163"
```
