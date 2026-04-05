# Postcode Comparison

A pre-built domain comparison for postcodes. Supports exact matching and
prefix-based partial matching. Optionally appends geographic distance
fallback levels when latitude and longitude columns are available.

## Usage

``` r
cl_postcode(
  term_frequency = FALSE,
  lat_col = NULL,
  long_col = NULL,
  km_thresholds = c(1, 10, 100)
)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by postcode frequency at the
  highest comparison level. Defaults to `FALSE`.

- lat_col, long_col:

  Character. Names of latitude and longitude columns. Both must be
  supplied together. When provided, geographic distance levels are
  appended before
  [`cl_else()`](http://christophertkenny.com/irelink/reference/cl_else.md).

- km_thresholds:

  Numeric vector of distance thresholds in kilometres, ordered from
  strictest to most lenient. Only used when `lat_col` and `long_col` are
  supplied. Defaults to `c(1, 10, 100)`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(postcode, cl_postcode())
#> Linkage Specification
#>   Comparisons (1):
#>     postcode : levels
#>   Blocking rules: (none)

# With geographic fallback (requires lat/lon columns in the data)
il_spec() |>
  il_compare(postcode, cl_postcode(lat_col = 'lat', long_col = 'lon'))
#> Linkage Specification
#>   Comparisons (1):
#>     postcode : levels
#>   Blocking rules: (none)
```
