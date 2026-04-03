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
block_on(..., .where = NULL, .transform = NULL)
```

## Arguments

- ...:

  Unquoted column names. Columns are AND-ed within a single `block_on()`
  call.

- .where:

  An optional raw SQL string for non-equality blocking conditions (e.g.,
  `"levenshtein(l.dob, r.dob) <= 1"`). When supplied alongside column
  names, the column equalities and the SQL condition are AND-ed
  together.

- .transform:

  An optional transform function applied to both left and right column
  values before the equality check. See
  [il_soundex](http://christophertkenny.com/irelink/reference/phonetic.md),
  [il_metaphone](http://christophertkenny.com/irelink/reference/phonetic.md),
  and
  [il_dmetaphone](http://christophertkenny.com/irelink/reference/phonetic.md).

## Value

A blocking-rule object for use in training verbs.

## Examples

``` r
block_on(first_name, surname)
#> $columns
#>                           
#> "first_name"    "surname" 
#> 
#> $where
#> NULL
#> 
#> $transform
#> NULL
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"

# Fuzzy SQL conditions
block_on(first_name, .where = 'levenshtein(l.dob, r.dob) <= 1')
#> $columns
#>              
#> "first_name" 
#> 
#> $where
#> [1] "levenshtein(l.dob, r.dob) <= 1"
#> 
#> $transform
#> NULL
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"

# Phonetic blocking
block_on(first_name, .transform = il_soundex)
#> $columns
#>              
#> "first_name" 
#> 
#> $where
#> NULL
#> 
#> $transform
#> function (x) 
#> {
#>     vapply(x, soundex_one, character(1), USE.NAMES = FALSE)
#> }
#> <bytecode: 0x55fcd6fa07a0>
#> <environment: namespace:irelink>
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"
```
