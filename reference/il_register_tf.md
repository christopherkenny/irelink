# Register Pre-Computed Term Frequency Tables

Allows you to supply pre-computed term frequency lookup tables instead
of having them computed automatically from the data. This is useful when
you have production TF tables from a larger dataset or want to reuse TF
values across multiple linkage runs.

## Usage

``` r
il_register_tf(model, col, tf_data, overwrite = FALSE)
```

## Arguments

- model:

  An `il_model` object.

- col:

  Character name of the comparison column.

- tf_data:

  A data frame with columns `<col>` and `tf_<col>`.

- overwrite:

  Logical. If `TRUE`, overwrite an existing TF table for this column.
  Defaults to `FALSE`.

## Value

The updated model, with the TF table registered in the database.

## Details

The supplied data must have exactly two columns: the value column (named
the same as the comparison column) and the frequency column (named
`tf_<col>`).

## Examples

``` r
if (FALSE) { # \dontrun{
# Suppose you have pre-computed TF for first_name
tf <- data.frame(
  first_name = c('John', 'Jane', 'Bob'),
  tf_first_name = c(0.15, 0.10, 0.05)
)
model <- il_register_tf(model, 'first_name', tf)
} # }
```
