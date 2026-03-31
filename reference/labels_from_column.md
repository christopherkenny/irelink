# Derive Pairwise Labels from a Ground-Truth Column

Given a model and a column name containing cluster or entity IDs,
generates pairwise labels for all predicted pairs. Two records sharing
the same value in `labels_col` are labelled as matches.

## Usage

``` r
labels_from_column(model, labels_col, threshold = 0)
```

## Arguments

- model:

  A trained `il_model` object.

- labels_col:

  A string naming the column in the original data that contains the
  ground-truth cluster or entity identifier.

- threshold:

  Match-probability threshold for selecting predicted pairs. Defaults to
  `0` to include all candidate pairs.

## Value

A data frame with columns `unique_id_l`, `unique_id_r`, and `is_match`
(integer 0/1).

## Details

This is a convenience wrapper: instead of manually building a labels
data frame with `unique_id_l`, `unique_id_r`, and `is_match`, you supply
the column name and let irelink derive everything.

## Examples

``` r
if (FALSE) { # \dontrun{
labels <- labels_from_column(model, "cluster")
il_accuracy(model, labels)
} # }
```
