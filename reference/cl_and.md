# Combine Comparison Conditions with AND

Creates a compound level that fires only when all supplied conditions
are satisfied.

## Usage

``` r
cl_and(...)
```

## Arguments

- ...:

  Comparison-level objects to AND together.

## Value

A comparison-level object.

## Examples

``` r
cl_and(cl_exact(), cl_jaro_winkler(0.9))
#> $method
#> [1] "and"
#> 
#> $children
#> $children[[1]]
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
#> $children[[2]]
#> $method
#> [1] "jaro_winkler"
#> 
#> $thresholds
#> [1] 0.9
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
