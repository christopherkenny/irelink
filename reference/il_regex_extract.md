# Regex Extraction Column Transform

Returns a transform that extracts a regex match from a string column.
Returns `NA` when no match is found. The result can be passed as the
`transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).
On DuckDB and DuckDB, the computation is pushed into SQL.

## Usage

``` r
il_regex_extract(pattern, group = 0L)
```

## Arguments

- pattern:

  A regular expression.

- group:

  Integer capture group to extract. Use `0` for the whole match, or a
  positive integer for a numbered capture group.

## Value

An `il_column_transform` closure.

## Examples

``` r
# Extract a 5-digit ZIP code from a freeform address string
tf <- il_regex_extract('\\d{5}')
tf(c('Apt 4, 90210', '10001-1234', 'no zip'))
#> [1] "90210" "10001" NA     
```
