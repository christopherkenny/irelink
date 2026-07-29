# Array Element Column Transform

Returns a transform that extracts the first or last element of an
array-valued column. The result can be passed as the `transform`
argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).
On DuckDB, maps to SQL array indexing (`col[1]` or `col[-1]`).

## Usage

``` r
il_array_element(position = c("first", "last"))
```

## Arguments

- position:

  Either `"first"` or `"last"`.

## Value

An `il_column_transform` closure.

## Examples

``` r
tf <- il_array_element('first')
tf(list(c('Alice', 'A'), c('Bob'), character(0)))
#> [1] "Alice" "Bob"   NA     
```
