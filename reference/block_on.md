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
block_on(..., .where = NULL, .transform = NULL, .explode = NULL)
```

## Arguments

- ...:

  Column names (bare or `column ~ transform` formulas). See
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
  for details on the formula syntax. Columns are AND-ed within a single
  `block_on()` call.

- .where:

  An optional raw SQL string for non-equality blocking conditions (e.g.,
  `"levenshtein(l.dob, r.dob) <= 1"`). When supplied alongside column
  names, the column equalities and the SQL condition are AND-ed
  together.

- .transform:

  An optional transform applied to every column that does not already
  have a formula transform. See
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
  for details.

- .explode:

  An optional character vector of array column names to unnest before
  blocking. See
  [`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
  for details.

## Value

A blocking-rule object for use in training verbs.

## Examples

``` r
block_on(first_name, surname)
#> $columns
#> [1] "first_name" "surname"   
#> 
#> $where
#> NULL
#> 
#> $transform
#> NULL
#> 
#> $explode
#> NULL
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"

# Fuzzy SQL conditions
block_on(first_name, .where = 'levenshtein(l.dob, r.dob) <= 1')
#> $columns
#> [1] "first_name"
#> 
#> $where
#> [1] "levenshtein(l.dob, r.dob) <= 1"
#> 
#> $transform
#> NULL
#> 
#> $explode
#> NULL
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"

# Phonetic blocking
block_on(first_name, .transform = il_soundex)
#> $columns
#> [1] "first_name"
#> 
#> $where
#> NULL
#> 
#> $transform
#> function (x) 
#> {
#>     vapply(x, soundex_one, character(1), USE.NAMES = FALSE)
#> }
#> <bytecode: 0x55909c676ee8>
#> <environment: namespace:irelink>
#> 
#> $explode
#> NULL
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"

# Per-column substring blocking
block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4))
#> $columns
#> [1] "first_name" "surname"   
#> 
#> $where
#> NULL
#> 
#> $transform
#> $transform$first_name
#> function (x) 
#> substr(x, start, start + length - 1L)
#> <bytecode: 0x55909c6e1058>
#> <environment: 0x55909c6e47f8>
#> attr(,"transform_type")
#> [1] "il_substr"
#> attr(,"params")
#> attr(,"params")$start
#> [1] 1
#> 
#> attr(,"params")$length
#> [1] 3
#> 
#> attr(,"class")
#> [1] "il_column_transform" "function"           
#> 
#> $transform$surname
#> function (x) 
#> substr(x, start, start + length - 1L)
#> <bytecode: 0x55909c6e1058>
#> <environment: 0x55909c6e53a0>
#> attr(,"transform_type")
#> [1] "il_substr"
#> attr(,"params")
#> attr(,"params")$start
#> [1] 1
#> 
#> attr(,"params")$length
#> [1] 4
#> 
#> attr(,"class")
#> [1] "il_column_transform" "function"           
#> 
#> 
#> $explode
#> NULL
#> 
#> attr(,"class")
#> [1] "il_blocking_rule"
```
