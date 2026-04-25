# Add a Prevalence Prior

Sets a target for the global match prevalence. With `strength = NULL`,
the target is used only as the model's starting prior. With a finite
strength, EM also uses the target as Beta pseudo-counts.

## Usage

``` r
il_prior_prevalence(model, probability, strength = NULL)
```

## Arguments

- model:

  An `il_model` object.

- probability:

  Target match probability, strictly between 0 and 1.

- strength:

  Optional non-negative effective sample size.

## Value

The model with prior metadata stored in `model$params$priors`.
