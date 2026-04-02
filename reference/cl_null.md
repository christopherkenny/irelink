# Null / Missing Value Level

Creates a level that fires when either or both record values are `NULL`
or `NA`. Typically used as the first level inside
[`cl_levels()`](http://christophertkenny.com/irelink/reference/cl_levels.md).

## Usage

``` r
cl_null()
```

## Value

A comparison-level object.

## Examples

``` r
cl_levels(cl_null(), cl_exact(), cl_else())
#> $method
#> [1] "levels"
#> 
#> $levels
#> $levels[[1]]
#> $method
#> [1] "null"
#> 
#> $is_null_level
#> [1] TRUE
#> 
#> $is_else_level
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "il_comparison_level"
#> 
#> $levels[[2]]
#> $method
#> [1] "exact"
#> 
#> $term_frequency
#> [1] FALSE
#> 
#> $is_null_level
#> [1] FALSE
#> 
#> $is_else_level
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "il_comparison_level"
#> 
#> $levels[[3]]
#> $method
#> [1] "else"
#> 
#> $is_null_level
#> [1] FALSE
#> 
#> $is_else_level
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "il_comparison_level"
#> 
#> 
#> $term_frequency
#> [1] FALSE
#> 
#> $is_null_level
#> [1] FALSE
#> 
#> $is_else_level
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "il_comparison_level"
```
