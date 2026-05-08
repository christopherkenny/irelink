# Create an Empty Linkage Specification

Initializes a blank `il_spec` object onto which comparison layers and
blocking rules are added with
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md)
and
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md).

## Usage

``` r
il_spec()
```

## Value

An `il_spec` object with no comparisons or blocking rules.

## Examples

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)
```
