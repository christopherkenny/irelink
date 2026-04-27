# Personal Name Comparison

A pre-built domain comparison for personal names. Combines exact
matching and Jaro-Winkler levels with thresholds tuned for typical name
variation. Optionally adds a Soundex phonetic level as a final fallback
before the else level, which helps catch names that sound similar but
are spelled differently (e.g., Smith/Smyth).

## Usage

``` r
cl_name(term_frequency = FALSE, phonetic = FALSE)
```

## Arguments

- term_frequency:

  Logical. If `TRUE`, adjust match weights by name frequency at the
  highest comparison level. Defaults to `FALSE`.

- phonetic:

  Logical. If `TRUE`, add a
  [`cl_soundex()`](http://christophertkenny.com/irelink/reference/cl_soundex.md)
  level as a fallback before the else level. Defaults to `FALSE`.

## Value

A comparison-level object for use in
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Examples

``` r
il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name(term_frequency = TRUE))
#> Linkage Specification
#>   Comparisons (2):
#>     first_name : levels
#>     surname : levels
#>   Blocking rules: (none)

il_spec() |>
  il_compare(first_name, cl_name(phonetic = TRUE))
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : levels
#>   Blocking rules: (none)
```
