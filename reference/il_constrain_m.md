# Add a Fixed Matched-Class Constraint

Fixes one comparison's matched-class `m` probabilities during EM. This
is a hard constraint, stored separately from regularizing priors.

## Usage

``` r
il_constrain_m(model, col, exact = NULL, levels = NULL)
```

## Arguments

- model:

  An `il_model` object.

- col:

  Comparison column, supplied as a bare name or string.

- exact:

  Probability for the strongest gamma level.

- levels:

  Complete named probability vector, with names such as `"0"`, `"1"`,
  and `"2"`.

## Value

The model with constraint metadata in `model$params$constraints`.
