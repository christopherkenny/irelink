# Add a Matched-Class Comparison Prior

Adds a Dirichlet regularizing prior for one comparison's matched-class
`m` probabilities. Use `exact` for the strongest agreement level, or
`levels` for a complete named gamma-level distribution.

## Usage

``` r
il_prior_m(
  model,
  col,
  exact = NULL,
  levels = NULL,
  strength,
  remainder = c("current")
)
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

- strength:

  Non-negative effective sample size.

- remainder:

  How to distribute non-exact probability. Currently `"current"` uses
  trained/current `m` probabilities when available and otherwise falls
  back to uniform.

## Value

The model with prior metadata stored in `model$params$priors`.
