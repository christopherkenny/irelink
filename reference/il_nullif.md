# Replace a Value with NA Column Transform

Returns a transform that replaces a specific value with `NA`. Commonly
used to convert empty strings to `NA` before comparison so that
missing-data levels are triggered correctly. The result can be passed as
the `transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).
On DuckDB and PostgreSQL, maps to SQL `NULLIF`.

## Usage

``` r
il_nullif(value)
```

## Arguments

- value:

  The value to treat as missing.

## Value

An `il_column_transform` closure.

## Examples

``` r
tf <- il_nullif('')
tf(c('New York', '', 'Chicago'))
#> [1] "New York" NA         "Chicago" 

# Use before comparison to treat blank city as missing
spec <- il_spec() |>
  il_compare(city, cl_exact(), transform = il_nullif(''))
```
