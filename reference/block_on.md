# Create a Training-Time Blocking Rule

Creates a blocking rule for use inside training verbs such as
[`il_estimate_em()`](http://christophertkenny.com/irelink/reference/il_estimate_em.md)
and
[`il_estimate_prior()`](http://christophertkenny.com/irelink/reference/il_estimate_prior.md).
This is distinct from
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md),
which adds prediction-time blocking to a specification. Analogous to
[`dplyr::join_by()`](https://dplyr.tidyverse.org/reference/join_by.html)
— a specification object that describes how to partition pairs during
training.

## Usage

``` r
block_on(...)
```

## Arguments

- ...:

  Unquoted column names. Columns are AND-ed within a single `block_on()`
  call.

## Value

A blocking-rule object for use in training verbs.

## Examples

``` r
block_on(first_name, surname)
#> $columns
#>                           
#> "first_name"    "surname" 
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"
```
