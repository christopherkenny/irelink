# Extract a Substring Column Transform

Returns a transform that extracts a fixed-width substring from a string
column. The result can be passed as the `transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).
On DuckDB, the computation is pushed into SQL.

## Usage

``` r
il_substr(start, length)
```

## Arguments

- start:

  Integer start position (1-indexed).

- length:

  Integer number of characters to extract.

## Value

An `il_column_transform` closure.

## Examples

``` r
tf <- il_substr(1, 3)
tf(c('Johnson', 'Smith', 'Lee'))
#> [1] "Joh" "Smi" "Lee"

# Use for blocking on the first 3 characters of a name
spec <- il_spec() |>
  il_block_on(last_name, .transform = il_substr(1, 3))
```
