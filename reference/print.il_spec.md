# Print an irelink Specification

Displays a human-readable summary of the comparisons and blocking rules
stored in an `il_spec` object.

## Usage

``` r
# S3 method for class 'il_spec'
print(x, ...)
```

## Arguments

- x:

  An `il_spec` object.

- ...:

  Additional arguments passed to
  [`print()`](https://rdrr.io/r/base/print.html).

## Value

`x`, invisibly.

## Examples

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_exact())
print(spec)
#> Linkage Specification
#>   Comparisons (1):
#>     first_name : exact
#>   Blocking rules: (none)
```
