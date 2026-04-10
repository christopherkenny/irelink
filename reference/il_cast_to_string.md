# Cast to String Column Transform

Returns a transform that casts any column to a character/VARCHAR type.
Useful when a numeric or date column needs to be compared as text. The
result can be passed as the `transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).
On DuckDB and PostgreSQL, maps to SQL `CAST(col AS VARCHAR)`.

## Usage

``` r
il_cast_to_string()
```

## Value

An `il_column_transform` closure.

## Examples

``` r
tf <- il_cast_to_string()
tf(c(12345L, 67890L))
#> [1] "12345" "67890"
```
