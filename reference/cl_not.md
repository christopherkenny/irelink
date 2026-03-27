# Negate a Comparison Condition

Creates a level that fires when the supplied condition does **not**
hold.

## Usage

``` r
cl_not(x)
```

## Arguments

- x:

  A comparison-level object to negate.

## Value

A comparison-level object.

## Examples

``` r
cl_not(cl_exact())
#> $method
#> [1] "not"
#> 
#> $child
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
#> $is_null_level
#> [1] FALSE
#> 
#> $is_else_level
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "il_comparison_level"
```
