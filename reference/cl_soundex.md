# Soundex Phonetic Comparison

Creates a comparison level based on the Soundex phonetic algorithm. Two
strings match if their Soundex codes are identical. This can be used as
a fallback level within
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md)
or
[`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md)
to catch names that sound similar but are spelled differently (e.g.,
Smith/Smyth, Robert/Rupert).

## Usage

``` r
cl_soundex()
```

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
or
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md).

## Details

On DuckDB, Soundex runs via a registered SQL MACRO. On SQLite, it falls
back to an R-side implementation.

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_soundex())
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : soundex
#>   Blocking rules: (none)

il_spec() |>
  il_compare(
    first_name,
    cl_levels(
      cl_null(),
      cl_exact(),
      cl_jaro_winkler(0.9),
      cl_soundex(),
      cl_else()
    )
  )
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
