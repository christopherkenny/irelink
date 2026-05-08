# Score Comparison Patterns

Scores an aggregated or row-level comparison-pattern table using a
trained model. Dependency-aware models use their fitted log-linear
pattern state. independent models use the fieldwise m/u parameters.

## Usage

``` r
il_score_patterns(model, patterns)
```

## Arguments

- model:

  A trained `il_model`.

- patterns:

  A data frame containing either comparison columns named like the model
  comparisons or gamma columns named `gamma_<comparison>`.

## Value

A tibble containing the input columns plus `match_weight` and
`total_match_weight`, and `match_probability`.
