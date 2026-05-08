# Try-Parse Timestamp Column Transform

Returns a transform that attempts to parse a string column as a
timestamp. Unlike
[`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html), failures
return `NA`/`NULL` rather than raising an error. On DuckDB this uses
`try_strptime()`, and on PostgreSQL it uses `TO_TIMESTAMP()`. The result
can be passed as the `transform` argument to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
and composed with other transforms via
[`il_transform()`](http://christophertkenny.com/irelink/reference/il_transform.md).

## Usage

``` r
il_try_parse_timestamp(format = "%Y-%m-%d %H:%M:%S")
```

## Arguments

- format:

  A `strptime`-style format string. Defaults to `"%Y-%m-%d %H:%M:%S"`.

## Value

An `il_column_transform` closure.

## Examples

``` r
tf <- il_try_parse_timestamp()
tf(c('2020-01-15 08:30:00', 'not-a-timestamp', '1985-06-30 12:00:00'))
#> [1] "2020-01-15 08:30:00" NA                    "1985-06-30 12:00:00"

# Custom format
tf2 <- il_try_parse_timestamp('%m/%d/%Y %I:%M %p')
tf2(c('01/15/2020 08:30 AM', 'bad'))
#> [1] "2020-01-15 08:30:00" NA                   
```
