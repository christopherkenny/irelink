# Combine Comparison Conditions with OR

Creates a compound level that fires when any of the supplied conditions
are satisfied.

## Usage

``` r
cl_or(...)
```

## Arguments

- ...:

  Comparison-level objects to OR together.

## Value

A comparison-level object.

## Examples

``` r
cl_or(cl_jaro_winkler(0.9), cl_levenshtein(1))
#> $method
#> [1] "or"
#> 
#> $children
#> $children[[1]]
#> $method
#> [1] "jaro_winkler"
#> 
#> $thresholds
#> [1] 0.9
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
#> [1] "levenshtein"
#> 
#> $thresholds
#> [1] 1
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
