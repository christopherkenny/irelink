# Try-Parse Date Column Transform

Returns a transform that attempts to parse a string column as a date.
Unlike [`as.Date()`](https://rdrr.io/r/base/as.Date.html), failures
return `NA`/`NULL` rather than raising an error — on DuckDB this uses
`try_strptime()`, on PostgreSQL `TO_DATE()`. The result can be passed as
the `transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).

## Usage

``` r
il_try_parse_date(format = "%Y-%m-%d")
```

## Arguments

- format:

  A `strptime`-style format string. Defaults to `"%Y-%m-%d"`.

## Value

An `il_column_transform` closure.

## Examples

``` r
tf <- il_try_parse_date()
tf(c('2020-01-15', 'not-a-date', '1985-06-30'))
#> [1] "2020-01-15" NA           "1985-06-30"

# Non-ISO format
tf2 <- il_try_parse_date('%m/%d/%Y')
tf2(c('01/15/2020', 'bad'))
#> [1] "2020-01-15" NA          
```
